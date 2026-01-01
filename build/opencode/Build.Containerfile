# --- STAGE 1: BUILDER ---
FROM docker.io/oven/bun:debian AS builder

ARG PYTHON_VERSION=3.14.5
ENV DEBIAN_FRONTEND=noninteractive

# 1. Install build tools + system Python
RUN --mount=type=bind,source=build/opencode/cache,target=/mnt/host_cache,rw,Z,U \
    rm -f /etc/apt/apt.conf.d/docker-clean && \
    mkdir -p /mnt/host_cache/apt_cache/partial && \
    echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-debs && \
    ln -sf /mnt/host_cache/apt_cache /var/cache/apt/archives && \
    apt-get update && apt-get install -y --no-install-recommends \
    build-essential git curl ca-certificates gnupg2 lsb-release \
    python3-pip python3-venv \
    libssl-dev zlib1g-dev libncurses5-dev libreadline-dev libsqlite3-dev \
    liblzma-dev libffi-dev \
    clang-19 llvm-19 llvm-19-dev

# 2. Setup Sigstore
RUN --mount=type=bind,source=build/opencode/cache,target=/mnt/host_cache,rw,Z,U \
    python3 -m venv /opt/sigstore-venv && \
    PIP_CACHE_DIR=/mnt/host_cache/pip_sigstore \
    /opt/sigstore-venv/bin/pip install sigstore

# 3. Download, Verify, and Compile Python
RUN --mount=type=bind,source=build/opencode/cache,target=/mnt/host_cache,rw,Z,U \
    mkdir -p /mnt/host_cache/python_src && \
    if [ -f "/mnt/host_cache/python_src/Python-${PYTHON_VERSION}.tar.xz" ]; then \
        cp "/mnt/host_cache/python_src/Python-${PYTHON_VERSION}.tar.xz" /tmp/ && \
        cp "/mnt/host_cache/python_src/Python-${PYTHON_VERSION}.tar.xz.sigstore" /tmp/; \
    else \
        curl -L -o "/tmp/Python-${PYTHON_VERSION}.tar.xz" "https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tar.xz" && \
        curl -L -o "/tmp/Python-${PYTHON_VERSION}.tar.xz.sigstore" "https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tar.xz.sigstore" && \
        cp "/tmp/Python-${PYTHON_VERSION}.tar.xz" /mnt/host_cache/python_src/ && \
        cp "/tmp/Python-${PYTHON_VERSION}.tar.xz.sigstore" /mnt/host_cache/python_src/; \
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

ENV PATH="/opt/python-${PYTHON_VERSION}/bin:${PATH}"
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
    rm -f /etc/apt/apt.conf.d/docker-clean && \
    mkdir -p /mnt/host_cache/apt_cache/partial && \
    echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-debs && \
    ln -sf /mnt/host_cache/apt_cache /var/cache/apt/archives && \
    apt-get update && apt-get install -y postgresql-server-dev-18

# 4. Compile OpenCode from source
WORKDIR /src/opencode
ENV BUN_CONFIG_MAX_WORKERS=1
ENV NODE_OPTIONS="--max-old-space-size=4096"

RUN --mount=type=bind,source=build/opencode/cache,target=/mnt/host_cache,rw,Z,U \
    --mount=type=bind,source=build/opencode/cache/latest_commit.txt,target=/tmp/latest_commit.txt \
    mkdir -p /mnt/host_cache/opencode_src && \
    cd /mnt/host_cache/opencode_src && \
    if [ ! -d "repo/.git" ]; then \
        echo "📥 Repository missing. Cloning fresh copy..." && \
        git clone --depth 1 https://github.com/anomalyco/opencode.git repo; \
    else \
        echo "🔄 Repository found. Syncing latest commits based on: $(cat /tmp/latest_commit.txt)" && \
        cd repo && \
        git pull; \
    fi && \
    cp -r /mnt/host_cache/opencode_src/repo/. /src/opencode/

RUN --mount=type=bind,source=build/opencode/cache,target=/mnt/host_cache,rw,Z,U \
    export HOME=/mnt/host_cache/bun && \
    export BUN_INSTALL_CACHE_DIR=$HOME/.bun/install/cache && \
    bun install --backend=copyfile --ignore-scripts --network-concurrency=1

RUN --mount=type=bind,source=build/opencode/cache,target=/mnt/host_cache,rw,Z,U \
    export HOME=/mnt/host_cache/bun && \
    export BUN_INSTALL_CACHE_DIR=$HOME/.bun/install/cache && \
    HUSKY=0 bun run --cwd packages/opencode fix-node-pty && \
    HUSKY=0 bun x turbo run build --filter=opencode --concurrency 1 && \
    mkdir -p /out && \
    cp packages/opencode/dist/opencode-linux-x64/bin/opencode /out/opencode

# 5. Compile pgvector
WORKDIR /src/pgvector

ARG PGVECTOR_VERSION=0.8.2

RUN --mount=type=bind,source=build/opencode/cache,target=/mnt/host_cache,rw,Z,U \
    mkdir -p /mnt/host_cache/pgvector_src && \
    if [ ! -d "/mnt/host_cache/pgvector_src/pgvector-${PGVECTOR_VERSION}" ]; then \
        git clone --branch "v${PGVECTOR_VERSION}" --depth 1 https://github.com/pgvector/pgvector.git "/mnt/host_cache/pgvector_src/pgvector-${PGVECTOR_VERSION}"; \
    fi && \
    cp -r "/mnt/host_cache/pgvector_src/pgvector-${PGVECTOR_VERSION}/." . && \
    make && \
    make install DESTDIR=/out/pg_assets

# 6. Install lean-ctx
ENV RUSTUP_HOME=/opt/rustup CARGO_HOME=/opt/cargo
ENV PATH="/opt/cargo/bin:${PATH}"
RUN curl --proto '=https' --tlsv1.3 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path

RUN --mount=type=bind,source=build/opencode/cache,target=/mnt/host_cache,rw,Z,U \
    CARGO_HOME=/mnt/host_cache/cargo \
    cargo install lean-ctx --root /out
