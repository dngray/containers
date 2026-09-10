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

# 1. Install build tools + system Python
RUN --mount=type=bind,source=build/opencode/cache,target=/mnt/host_cache,rw,Z,U \
    rm -f /etc/apt/apt.conf.d/docker-clean && \
    mkdir -p /mnt/host_cache/apt_cache/partial && chmod 755 /mnt/host_cache/apt_cache/partial && \
    echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-debs && \
    ln -sf /mnt/host_cache/apt_cache /var/cache/apt/archives && \
    apt-get update && apt-get install -y --no-install-recommends \
    build-essential git curl ca-certificates gnupg2 lsb-release \
    python3-pip python3-venv \
    libssl-dev zlib1g-dev libncurses5-dev libreadline-dev libsqlite3-dev \
    liblzma-dev libffi-dev \
    clang-19 llvm-19 llvm-19-dev

# 2. Setup Sigstore
RUN python3 -m venv /opt/sigstore-venv && \
    /opt/sigstore-venv/bin/pip install sigstore

# 3. Download, Verify, and Compile Python
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

RUN apt-get update && apt-get install -y postgresql-server-dev-18

# 4. Compile OpenCode from source
WORKDIR /src/opencode
ENV BUN_CONFIG_MAX_WORKERS=1
ENV NODE_OPTIONS="--max-old-space-size=4096"

RUN cd ${CACHE_DIR}/opencode_src && \
    if [ ! -d "repo/.git" ]; then \
        echo "📥 Repository missing. Cloning fresh copy..." && \
        git clone --depth 1 https://github.com/anomalyco/opencode.git repo; \
    else \
        echo "🔄 Repository found. Syncing latest commits based on: $(cat /tmp/latest_commit.txt)" && \
        cd repo && git pull; \
    fi && \
    cp -r ${CACHE_DIR}/opencode_src/repo/. /src/opencode/

RUN export HOME=${CACHE_DIR}/bun && \
    bun install --backend=copyfile --ignore-scripts --network-concurrency=1

RUN export HOME=${CACHE_DIR}/bun && \
    HUSKY=0 bun run --cwd packages/core fix-node-pty && \
    HUSKY=0 bun x turbo run build --filter=opencode --concurrency 1 && \
    mkdir -p /out && \
    cp packages/opencode/dist/opencode-linux-x64/bin/opencode /out/opencode

# 5. Compile pgvector
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
    cargo install lean-ctx --version 3.9.16 --root /out
