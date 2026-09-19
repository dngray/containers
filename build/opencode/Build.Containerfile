# --- STAGE 1: BUILDER ---
FROM docker.io/oven/bun:debian AS builder

ARG PYTHON_VERSION=3.14.7
ENV DEBIAN_FRONTEND=noninteractive

# Global paths mapped directly to your mount point
ENV CACHE_DIR="/mnt/host_cache" \
    PIP_CACHE_DIR="/mnt/host_cache/pip_sigstore" \
    BUN_INSTALL_CACHE_DIR="/mnt/host_cache/bun/.bun/install/cache" \
    CARGO_HOME="/mnt/host_cache/cargo" \
    RUSTUP_HOME="/opt/rustup" \
    PATH="/mnt/host_cache/cargo/bin:/opt/python-${PYTHON_VERSION}/bin:${PATH}"

# Install build tools + system Python
RUN --mount=type=bind,source=build/opencode/cache,target=/mnt/host_cache,rw,Z,U \
    mkdir -p /mnt/host_cache/apt_cache && \
    rm -f /etc/apt/apt.conf.d/*clean* && \
    echo 'APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/01keep-debs && \
    echo 'Dir::Cache::archives "/mnt/host_cache/apt_cache";' >> /etc/apt/apt.conf.d/01keep-debs && \
    apt-get update && apt-get install -y --no-install-recommends \
    build-essential git curl ca-certificates gnupg2 lsb-release \
    python3-pip python3-venv \
    libssl-dev zlib1g-dev libncurses5-dev libreadline-dev libsqlite3-dev \
    liblzma-dev libffi-dev \
    clang-19 llvm-19 llvm-19-dev

# Setup Sigstore
RUN python3 -m venv /opt/sigstore-venv && \
    /opt/sigstore-venv/bin/pip install sigstore

# Download, Verify, and Compile Python
RUN if [ -f "${CACHE_DIR}/python_src/Python-${PYTHON_VERSION}.tar.xz" ]; then \
        cp "${CACHE_DIR}/python_src/Python-${PYTHON_VERSION}.tar.xz" /tmp/ && \
        cp "${CACHE_DIR}/python_src/Python-${PYTHON_VERSION}.tar.xz.sigstore" /tmp/; \
    else \
        curl -L -o "/tmp/Python-${PYTHON_VERSION}.tar.xz" "https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tar.xz" && \
        curl -L -o "/tmp/Python-${PYTHON_VERSION}.tar.xz.sigstore" "https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tar.xz.sigstore" && \
        cp "/tmp/Python-${PYTHON_VERSION}.tar.xz" ${CACHE_DIR}/python_src/ && \
        cp "/tmp/Python-${PYTHON_VERSION}.tar.xz.sigstore" ${CACHE_DIR}/python_src/; \
    fi && \
    cd /tmp && \
    /opt/sigstore-venv/bin/python3 -m sigstore verify identity \
        --bundle "Python-${PYTHON_VERSION}.tar.xz.sigstore" \
        --cert-identity "hugo@python.org" \
        --cert-oidc-issuer "https://github.com/login/oauth" \
        "Python-${PYTHON_VERSION}.tar.xz" && \
    tar -xf "Python-${PYTHON_VERSION}.tar.xz" && \
    cd "Python-${PYTHON_VERSION}" && \
    ./configure --enable-optimizations --with-lto --enable-experimental-jit --prefix="/opt/python-${PYTHON_VERSION}" && \
    make -j$(nproc) && \
    make install && \
    rm -rf "/tmp/Python-${PYTHON_VERSION}" "/tmp/Python-${PYTHON_VERSION}.tar.xz" "/tmp/Python-${PYTHON_VERSION}.tar.xz.sigstore"

RUN ln -s "/opt/python-${PYTHON_VERSION}/bin/python3" /usr/local/bin/python

RUN curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | \
    gpg --dearmor -o /usr/share/keyrings/postgresql.gpg

RUN tee /etc/apt/sources.list.d/pgdg.sources <<EOF
Types: deb
URIs: https://apt.postgresql.org/pub/repos/apt
Suites: $(lsb_release -cs)-pgdg
Components: main
Signed-By: /usr/share/keyrings/postgresql.gpg
EOF

RUN --mount=type=bind,source=build/opencode/cache,target=/mnt/host_cache,rw,Z,U \
    apt-get update && apt-get install -y postgresql-server-dev-18

# Compile OpenCode from official use binary
ARG RESOLVED_VERSION=1.17.0
ARG OPENCODE_TAG=v1.17.0
ARG OPENCODE_SOURCE=source
WORKDIR /src/opencode

ENV BUN_CONFIG_MAX_WORKERS=1
ENV NODE_OPTIONS="--max-old-space-size=4096"

RUN set -e; \
    if [ "${OPENCODE_SOURCE}" = "official" ]; then \
        echo "📥 Resolving pinned official OpenCode release digest (${OPENCODE_TAG})..." && \
        _digest=$(curl -fsSL "https://api.github.com/repos/anomalyco/opencode/releases/tags/${OPENCODE_TAG}" | \
                  jq -r '.assets[] | select(.name == "opencode-linux-x64.tar.gz") | .digest') && \
        echo "🔒 Digest locked: ${_digest}" && \
        curl -fL --retry 3 -o /tmp/opencode-linux-x64.tar.gz \
          "https://github.com/anomalyco/opencode/releases/download/${OPENCODE_TAG}/opencode-linux-x64.tar.gz" && \
        echo "${_digest}  /tmp/opencode-linux-x64.tar.gz" | sha256sum -c - && \
        mkdir -p /out && \
        tar -xzf /tmp/opencode-linux-x64.tar.gz -C /out && \
        chmod +x /out/opencode && \
        rm -f /tmp/opencode-linux-x64.tar.gz; \
    elif [ "${OPENCODE_SOURCE}" = "source" ]; then \
        echo "🧱 Compiling OpenCode from source (${OPENCODE_TAG})..." && \
        cd ${CACHE_DIR}/opencode_src && \
        if [ ! -d "repo/.git" ]; then \
            echo "📥 Repository missing. Cloning stable release tag ${OPENCODE_TAG}..." && \
            git clone --branch "${OPENCODE_TAG}" --depth 1 https://github.com/anomalyco/opencode.git repo; \
        else \
            echo "🔄 Repository found. Syncing and switching to stable tag ${OPENCODE_TAG}..." && \
            cd repo && \
            git fetch --tags --depth 1 origin "${OPENCODE_TAG}" && \
            git checkout FETCH_HEAD; \
        fi && \
        cp -r ${CACHE_DIR}/opencode_src/repo/. /src/opencode/ && \
        export HOME=${CACHE_DIR}/bun && \
        bun install --backend=copyfile --ignore-scripts --network-concurrency=1 && \
        REAL_VER="${RESOLVED_VERSION:-1.18.31}" && \
        HUSKY=0 bun run --cwd packages/core fix-node-pty && \
        export OPENCODE_VERSION="${REAL_VER}" && \
        export OPENCODE_CHANNEL="prod" && \
        export HUSKY=0 && \
        bun x turbo run build --filter=opencode --concurrency 1 --env-mode=loose -- --single && \
        mkdir -p /out && \
        cp packages/opencode/dist/opencode-linux-x64/bin/opencode /out/opencode; \
    else \
        echo "Unknown OPENCODE_SOURCE: '${OPENCODE_SOURCE}' (expected official or source)" >&2; \
        exit 1; \
    fi

# Compile pgvector
WORKDIR /src/pgvector

ARG PGVECTOR_VERSION=0.8.2

RUN if [ ! -d "${CACHE_DIR}/pgvector_src/pgvector-${PGVECTOR_VERSION}" ]; then \
        git clone --branch "v${PGVECTOR_VERSION}" --depth 1 https://github.com/pgvector/pgvector.git "/mnt/host_cache/pgvector_src/pgvector-${PGVECTOR_VERSION}"; \
    fi && \
    cp -r "${CACHE_DIR}/pgvector_src/pgvector-${PGVECTOR_VERSION}/." . && \
    make && \
    make install DESTDIR=/out/pg_assets

# 6. Install lean-ctx
RUN curl --proto '=https' --tlsv1.3 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path && \
    . "/mnt/host_cache/cargo/env" && \
    CARGO_BUILD_JOBS=1 cargo install lean-ctx --root /out --jobs 1
