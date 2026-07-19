# --- STAGE 2: RUNNER ---
FROM docker.io/debian:trixie-slim AS runner
ARG PYTHON_VERSION=3.14.6
ENV DEBIAN_FRONTEND=noninteractive

ARG HOST_UID=1000
ARG HOST_GID=1000

ARG COMPILER_IMAGE=opencode-compiler:latest

# 1. Bring in Python from our compiler image asset
COPY --from=$COMPILER_IMAGE "/opt/python-${PYTHON_VERSION}" "/opt/python-${PYTHON_VERSION}"
ENV PATH="/opt/python-${PYTHON_VERSION}/bin:${PATH}"

RUN ln -s "/opt/python-${PYTHON_VERSION}/bin/python3" /usr/local/bin/python3 && \
    ln -s "/opt/python-${PYTHON_VERSION}/bin/python3" /usr/local/bin/python${PYTHON_VERSION}

# 2. Restore runtime dependencies
RUN --mount=type=bind,source=build/opencode/cache,target=/mnt/host_cache,rw,Z,U \
    rm -f /etc/apt/apt.conf.d/docker-clean && \
    echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-debs && \
    ln -sf /mnt/host_cache/apt_cache /var/cache/apt/archives && \
    apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl gnupg2 lsb-release gcc libc6-dev \
    coreutils fd-find findutils fzf gawk git jq ripgrep sed util-linux \
    libfftw3-double3 libfftw3-single3 libopenblas0-pthread shellcheck \
    libgomp1 libopenblas-dev \
    && ln -s $(which fdfind) /usr/local/bin/fd

COPY build/opencode/roots.pem /usr/local/share/ca-certificates/roots.crt
RUN chmod 644 /usr/local/share/ca-certificates/roots.crt && update-ca-certificates

ENV CURL_CA_BUNDLE="/etc/ssl/certs/ca-certificates.crt" \
    SSL_CERT_FILE="/etc/ssl/certs/ca-certificates.crt"

COPY --from=$COMPILER_IMAGE /usr/share/keyrings/postgresql.gpg /usr/share/keyrings/postgresql.gpg
COPY --from=$COMPILER_IMAGE /etc/apt/sources.list.d/pgdg.sources /etc/apt/sources.list.d/pgdg.sources

RUN --mount=type=bind,source=build/opencode/cache,target=/mnt/host_cache,rw,Z,U \
    rm -f /etc/apt/apt.conf.d/docker-clean && \
    echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-debs && \
    ln -sf /mnt/host_cache/apt_cache /var/cache/apt/archives && \
    apt-get update && apt-get install -y postgresql-client-18 libpq-dev

# 3. Copy Compiled Assets straight from compiler image layout
COPY --from=$COMPILER_IMAGE /out/opencode /usr/local/bin/opencode
COPY --from=$COMPILER_IMAGE /out/pg_assets /

# 4. Copy uv tools
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

# 5. Use them to create the user
RUN groupadd -f -g $HOST_GID opencode || true && \
    useradd -m -u $HOST_UID -g $HOST_GID -s /bin/bash opencode
WORKDIR /home/opencode/workspace

# 6. Python Dependency Step
RUN --mount=type=bind,source=build/opencode/cache,target=/mnt/host_cache,rw,Z,U \
    uv pip install \
        --system \
        --cache-dir /mnt/host_cache/uv \
        --compile-bytecode \
        maturin puccinialin numpy psycopg psycopg_pool pytest fastembed pandas && \
    rm -f /etc/apt/apt.conf.d/docker-clean && \
    echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-debs && \
    ln -sf /mnt/host_cache/apt_cache /var/cache/apt/archives && \
    apt-get update && apt-get install -y --no-install-recommends nodejs npm && \
    rm -rf /home/opencode/workspace/.uv_cache \
           /home/opencode/.npm \
           /home/opencode/.cache/bun && \
    chown -R opencode:opencode /home/opencode

RUN set -e; \
    mkdir -p /home/opencode/.config/opencode /home/opencode/.local/bin; \
    cat > /home/opencode/.config/opencode/opencode.json <<'ENDJSON'
{
  "mcp": {
    "semble": { "type": "local", "command": ["semble"] },
    "codebase_memory": { "type": "local", "command": ["code-index-mcp"] },
    "repomix": { "type": "local", "command": ["repomix", "--mcp"] },
    "lean_ctx": { "type": "local", "command": ["lean-ctx", "mcp"] }
  },
  "lsp": {
    "python": {
      "command": ["pylsp"],
      "extensions": [".py"]
    },
    "bash": {
      "command": ["bash-language-server", "start"],
      "extensions": [".sh", ".bash", ".bashrc", ".profile"]
    }
  }
}
ENDJSON

RUN chown -R opencode:opencode /home/opencode/.config /home/opencode/.local
COPY --from=$COMPILER_IMAGE /out/bin/lean-ctx /home/opencode/.local/bin/lean-ctx

ENV PATH="/home/opencode/.local/bin:/opt/python-${PYTHON_VERSION}/bin:/usr/local/bin:$PATH"
USER opencode

# Install SeMBLe and code-index-mcp locally in user-space
RUN uv tool install --with mcp "semble[mcp]" && \
    uv tool install "code-index-mcp" && \
    uv tool install "python-lsp-server"

ENV NPM_CONFIG_PREFIX="/home/opencode/.local"
RUN npm install -g repomix bash-language-server

RUN opencode --version

ENTRYPOINT ["opencode"]

# --- STAGE 3: CLIENT TUI ---
FROM docker.io/debian:trixie-slim AS tui
ARG HOST_UID=1000
ARG HOST_GID=1000
ARG COMPILER_IMAGE=opencode-compiler:latest

# Pull the binary straight from the saved local compiler container asset
COPY --from=$COMPILER_IMAGE /out/opencode /usr/local/bin/opencode

RUN groupadd -f -g $HOST_GID opencode || true && \
    useradd -m -u $HOST_UID -g $HOST_GID -s /bin/bash opencode
USER opencode
ENTRYPOINT ["opencode"]
