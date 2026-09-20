#!/bin/bash
# apps/opencode/buildah-build.sh
#
# Imperative buildah pipeline for the opencode container catalog.
#
# ---------------------------------------------------------------------------
# Model
# ---------------------------------------------------------------------------
# Every expensive / deterministic step is built ONCE as its own committed
# layer image and pushed to ${REG_URL}/library/opencode/... Compose of a
# runnable variant is then nothing more than "picking" which layer images
# to merge, so an opencode tag bump only rebuilds the ocbin layer (and the
# finals) -- it NEVER recompiles Python, lean-ctx, or pgvector.
#
# Layer  catalog (all under "${REG_URL}/library/opencode"):
#   base          v1                Debian runtime + tools + opencode user
#   tui-base      v1                slim Debian for the attach-only TUI
#   pydex         <PYVER>           sigstore-verified Python-from-source
#   ocbin-source  <hash>            opencode compiled from source (bun/turbo)
#   ocbin-binary  <hash>            pinned upstream, sha256-verified release
#   pgassets      <PGVER>           pgclient + pgvector (payload staging dir)
#   rusttools     latest            lean-ctx built from crates.io
#   uvbin         latest            uv / uvx binaries on a scratch rootfs
#   mcp           latest            MCP/LSP tools payload in /home/opencode/.local
#
# Variant  matrix (STACK x SRC) -> which layers final images pick:
#   full + source   pydex + pgassets + rusttools + ocbin-source (default)
#   full + binary   pydex + pgassets + rusttools + ocbin-binary
#   basic + source  base                + ocbin-source (Debian python, slim)
#   basic + binary  base                + ocbin-binary
# Every variant also merges uvbin and mcp. The tui image is tui-base + ocbin.
#
# opencode.json is copied verbatim from build/opencode/opencode.jsonc
# (the full-stack config); the basic stack drops the lean_ctx entry via jq.
#
# ---------------------------------------------------------------------------
# Environment (set by apps/opencode/opencode.sh or lib/cli.sh)
# ---------------------------------------------------------------------------
#   REQUIRED  REG_URL       private registry host
#   REQUIRED  RESOLVED_HASH 7-char tag hash that tags/shames ocbin layers
#   REQUIRED  OPENCODE_TAG  git tag / release tag, default v${LATEST_VERSION}
#   OPTIONAL  LATEST_VERSION, HOST_UID, HOST_GID (lib/cli.sh), STACK, SRC,
#             TAIL, BUILD_JOBS (parallelism, default nproc),
#             PYTHON_VERSION (default 3.14.7), PGVECTOR_VERSION (default 0.8.2),
#             NO_PUSH=1 (commit locally without registry push)
#
# ---------------------------------------------------------------------------
# Notes
# ---------------------------------------------------------------------------
#   * `buildah mount` needs an unshared user+mount namespace when running
#     rootless, so the script re-execs itself once under `buildah unshare`.
#   * The host cache bind-mounts carry no SELinux label: build-time access is
#     fine unlabelled, and the runtime label comes from the ai_fortress policy
#     (`--security-opt label=type:fortress_agent_t` in bin/ai-secure).
#
# Subcommands: layers | server | tui | build

set -euo pipefail

# shellcheck disable=SC1007  # repo-convention empty assignment in CDPATH= cd
REPO_ROOT=$(CDPATH= cd "$(dirname "$0")/../.." && pwd)
. "${REPO_ROOT}/lib/cli.sh"

# Inside `buildah unshare` the invoking user is remapped to namespace root, so
# the re-sourced lib/cli.sh would recompute HOST_UID/HOST_GID as 0. Stash the
# host values in the first invocation and restore them in the re-exec so build
# layers create the `opencode` user with the host uid/gid.
if [ -n "${_BUILDAH_UNSHARED:-}" ] && [ -n "${_HOST_UID_FOR_UNSHARE:-}" ]; then
  HOST_UID="${_HOST_UID_FOR_UNSHARE}"
  HOST_GID="${_HOST_GID_FOR_UNSHARE}"
  export HOST_UID HOST_GID
fi

# merge_payload() needs `buildah mount`, which in rootless mode requires an
# unshared user+mount namespace. Re-exec under `buildah unshare` exactly once
# (the marker env prevents a re-entry loop; root invocations skip this).
if [ "$(id -u)" -ne 0 ] && [ -z "${_BUILDAH_UNSHARED:-}" ]; then
  export _BUILDAH_UNSHARED=1
  export _HOST_UID_FOR_UNSHARE="${HOST_UID}" _HOST_GID_FOR_UNSHARE="${HOST_GID}"
  exec buildah unshare "$0" "$@"
fi

# ---------------------------------------------------------------------------
# Globals
# ---------------------------------------------------------------------------
NS="${REG_URL}/library/opencode"          # namespace for every layer/final image
CACHE="${REPO_ROOT}/build/opencode/cache" # host-side build cache (source, tarballs, debs)
DL="${CACHE}/opencode_dl"                 # downloaded opencode release tarballs
STAGE="${CACHE}/buildah_stage"            # scratch area for compose-time files

PYVER="${PYTHON_VERSION:-3.14.7}"
PGVER="${PGVECTOR_VERSION:-0.8.2}"
BUILD_JOBS="${BUILD_JOBS:-$(nproc)}"

: "${OPENCODE_TAG:=v${LATEST_VERSION:-1.18.31}}"
: "${RESOLVED_HASH:?resolve_version must run first}"

BASE_IMG="${NS}/base:v1"
TUI_BASE_IMG="${NS}/tui-base:v1"
PYDEX_IMG="${NS}/pydex:${PYVER}"
PGA_IMG="${NS}/pgassets:${PGVER}"
RUST_IMG="${NS}/rusttools:latest"
UVBIN_IMG="${NS}/uvbin:latest"
MCP_IMG="${NS}/mcp:latest"
OC_SRC_IMG="${NS}/ocbin-source:${RESOLVED_HASH}"
OC_BIN_IMG="${NS}/ocbin-binary:${RESOLVED_HASH}"
SERVER_IMG="${NS}/opencode-server"
TUI_IMG="${NS}/opencode-tui"

# apt tweaks: keep downloaded debs and redirect them onto the host cache so
# every build layer shares one package cache (bind-mounted at /mnt/host_cache).
APTDROP='rm -f /etc/apt/apt.conf.d/*clean*; printf "APT::Keep-Downloaded-Packages \"true\";\n" > /etc/apt/apt.conf.d/01keep-debs; printf "Dir::Cache::archives \"/mnt/host_cache/apt_cache\";\n" >> /etc/apt/apt.conf.d/01keep-debs'

mkdir -p "${DL}" "${STAGE}" "${CACHE}/apt_cache/partial"

# ---------------------------------------------------------------------------
# img_exists(<image>)
#
# Description: true if an image with that name (or ID) already exists in the
#   local buildah store. Local existence is the layer "cache".
# Args:
#   $1  image (string): name, with tag, to look up
# Returns:
#   0 if the image exists, 1 otherwise.
# ---------------------------------------------------------------------------
img_exists() {
  [ -n "$(buildah images -q "$1" 2>/dev/null)" ]
}

# ---------------------------------------------------------------------------
# ensure(<layer_name>, <image>)
#
# Description: idempotent layer build+push. If <image> is already present
#   locally it is reused; otherwise the matching build_<layer_name> function
#   runs and the result is pushed to the registry (unless NO_PUSH=1).
# Args:
#   $1  layer_name (string): basename selecting build_${layer_name}()
#   $2  image (string): fully-qualified image name to commit/push
# Globals:
#   BUILD_JOBS (int): parallelism, read for the build log line
#   NO_PUSH (int): "1" commits locally without a registry push
# Outputs:
#   None directly; side effect is a new layer image and an optional push
# ---------------------------------------------------------------------------
ensure() {
  if img_exists "$2"; then
    ok " Layer ready: $1 ($2)"
  else
    info "==> Building layer: $1 ($2) [BUILD_JOBS=${BUILD_JOBS}]"
    "build_${1}"
    if [ "${NO_PUSH:-0}" = 1 ]; then
      ok " Committed locally (NO_PUSH=1): $2"
    else
      buildah push "$2"
      ok " Pushed layer: $2"
    fi
  fi
}

# ---------------------------------------------------------------------------
# ocbin_for(<src>)
#
# Description: returns the ocbin layer image matching the requested opencode
#   provenance.
# Args:
#   $1  src (string): "binary" (pinned, sha256-verified release) or
#       "source" (compiled)
# Globals:
#   OC_BIN_IMG (string): image name returned for src=binary
#   OC_SRC_IMG (string): image name returned for src=source
# Returns:
#   Prints the chosen ocbin image name to stdout
# ---------------------------------------------------------------------------
ocbin_for() {
  [ "$1" = binary ] && echo "${OC_BIN_IMG}" || echo "${OC_SRC_IMG}"
}

# ---------------------------------------------------------------------------
# build_base()
#
# Description: Debian runtime foundation for the server. Installs the tool
#   layer for both stacks, seeds the repo CA bundle, and creates the
#   `opencode` user/workspace reflecting the host uid/gid, then commits.
# Globals:
#   HOST_UID (int): `opencode` user uid, from lib/cli.sh
#   HOST_GID (int): group gid for the opencode user, from lib/cli.sh
#   CACHE (string): host cache dir bind-mounted at /mnt/host_cache
#   APTDROP (string): apt snippet pinning debs to the host cache
#   BASE_IMG (string): image name committed when complete
# Outputs:
#   Commits ${BASE_IMG}
# ---------------------------------------------------------------------------
build_base() {
  local container
  container=$(buildah from docker.io/library/debian:trixie-slim)
  buildah config --env DEBIAN_FRONTEND=noninteractive "$container"
  buildah run --volume "${CACHE}:/mnt/host_cache" "$container" -- bash -ec "
    set -e
    mkdir -p /mnt/host_cache/apt_cache/partial
    ${APTDROP}
    apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl gcc libc6-dev coreutils fd-find findutils fzf gawk \
      git jq ripgrep sed util-linux shellcheck nodejs npm python3 python3-venv
    ln -sf \"\$(command -v fdfind)\" /usr/local/bin/fd
  "
  buildah copy "$container" "${REPO_ROOT}/build/opencode/roots.pem" /usr/local/share/ca-certificates/roots.crt
  buildah run "$container" -- bash -ec '
    chmod 644 /usr/local/share/ca-certificates/roots.crt && update-ca-certificates
  '
  buildah config --env CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt "$container"
  buildah config --env SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt "$container"
  buildah config --env HOME=/home/opencode "$container"
  buildah run "$container" -- bash -ec "
    groupadd -f -g ${HOST_GID} opencode
    useradd -m -u ${HOST_UID} -g 0 -s /bin/bash opencode
    mkdir -p /home/opencode/workspace
    chown -R ${HOST_UID}:0 /home/opencode
  "
  buildah commit --rm "$container" "${BASE_IMG}"
}

# ---------------------------------------------------------------------------
# build_tui_base()
#
# Description: minimal Debian for the attach-only TUI client (no compilers,
#   no node, just the CA trust and the opencode xdg state dirs).
# Globals:
#   HOST_UID (int): `opencode` user uid, from lib/cli.sh
#   HOST_GID (int): group gid for the opencode user, from lib/cli.sh
#   CACHE (string): host cache dir bind-mounted at /mnt/host_cache
#   APTDROP (string): apt snippet pinning debs to the host cache
#   TUI_BASE_IMG (string): image name committed when complete
# Outputs:
#   Commits ${TUI_BASE_IMG}
# ---------------------------------------------------------------------------
build_tui_base() {
  local container
  container=$(buildah from docker.io/library/debian:trixie-slim)
  buildah config --env DEBIAN_FRONTEND=noninteractive "$container"
  buildah run --volume "${CACHE}:/mnt/host_cache" "$container" -- bash -ec "
    set -e
    mkdir -p /mnt/host_cache/apt_cache/partial
    ${APTDROP}
    apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl coreutils jq git
  "
  buildah copy "$container" "${REPO_ROOT}/build/opencode/roots.pem" /usr/local/share/ca-certificates/roots.crt
  buildah run "$container" -- bash -ec '
    chmod 644 /usr/local/share/ca-certificates/roots.crt && update-ca-certificates
  '
  buildah config --env CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt "$container"
  buildah config --env SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt "$container"
  buildah config --env HOME=/home/opencode "$container"
  buildah run "$container" -- bash -ec "
    groupadd -f -g ${HOST_GID} opencode
    useradd -m -u ${HOST_UID} -g 0 -s /bin/bash opencode
    mkdir -p /home/opencode/workspace /home/opencode/.config/opencode \
      /home/opencode/.local/share/opencode /home/opencode/.local/state/opencode \
      /home/opencode/.cache/opencode
    chown -R ${HOST_UID}:0 /home/opencode
  "
  buildah commit --rm "$container" "${TUI_BASE_IMG}"
}

# ---------------------------------------------------------------------------
# build_pydex()
#
# Description: installs CPython into /opt/python-<PYVER> from a sigstore
#   VERIFIED release tarball (identity hugo@python.org, GitHub OIDC) with
#   optimizations + LTO + experimental JIT, then commits. The tarball and
#   provenance bundle are cached on the host so verification only happens
#   once. Requires clang-19/llvm-19 for the JIT build.
# Globals:
#   PYVER (string): CPython version; selects tarball, /opt prefix and tag
#   BUILD_JOBS (int): parallelism for the CPython make
#   CACHE (string): host cache dir; python tarball + sigstore bundle cached
#   PYDEX_IMG (string): image name committed when complete
# Outputs:
#   Commits ${PYDEX_IMG}; adds /usr/local/bin/python3 + python<PYVER> symlinks
# ---------------------------------------------------------------------------
build_pydex() {
  local container python_tarball python_sigstore_bundle
  container=$(buildah from "${BASE_IMG}")
  python_tarball="Python-${PYVER}.tar.xz"
  python_sigstore_bundle="Python-${PYVER}.tar.xz.sigstore"
  buildah run --volume "${CACHE}:/mnt/host_cache" "$container" -- bash -ec "
    set -e
    apt-get update && apt-get install -y --no-install-recommends \
      build-essential libssl-dev zlib1g-dev libncurses5-dev libreadline-dev \
      libsqlite3-dev liblzma-dev libffi-dev clang-19 llvm-19 llvm-19-dev
    python3 -m venv /opt/sigstore-venv
    /opt/sigstore-venv/bin/pip install sigstore
    if [ -f /mnt/host_cache/python_src/${python_tarball} ]; then
      cp /mnt/host_cache/python_src/${python_tarball} /tmp/
      cp /mnt/host_cache/python_src/${python_sigstore_bundle} /tmp/
    else
      curl -fL -o /tmp/${python_tarball} https://www.python.org/ftp/python/${PYVER}/${python_tarball}
      curl -fL -o /tmp/${python_sigstore_bundle} https://www.python.org/ftp/python/${PYVER}/${python_sigstore_bundle}
      mkdir -p /mnt/host_cache/python_src
      cp /tmp/${python_tarball} /tmp/${python_sigstore_bundle} /mnt/host_cache/python_src/
    fi
    cd /tmp
    /opt/sigstore-venv/bin/python3 -m sigstore verify identity \
      --bundle /tmp/${python_sigstore_bundle} \
      --cert-identity hugo@python.org \
      --cert-oidc-issuer https://github.com/login/oauth \
      /tmp/${python_tarball}
    tar -xf /tmp/${python_tarball}
    cd /tmp/Python-${PYVER}
    ./configure --enable-optimizations --with-lto --enable-experimental-jit \
      --prefix=/opt/python-${PYVER}
    make -j${BUILD_JOBS}
    make install
    cd /tmp && rm -rf Python-${PYVER} /tmp/${python_tarball} /tmp/${python_sigstore_bundle}
  "
  buildah run "$container" -- bash -ec "
    ln -sf /opt/python-${PYVER}/bin/python3 /usr/local/bin/python3
    ln -sf /opt/python-${PYVER}/bin/python3 /usr/local/bin/python${PYVER}
  "
  buildah commit --rm "$container" "${PYDEX_IMG}"
}

# ---------------------------------------------------------------------------
# build_ocbin_source()
#
# Description: builds the opencode binary from the pinned git tag using the
#   official bun base image. The source tree and bun dependency cache live
#   on the host so repeat runs are incremental (git fetch + no-op install).
# Globals:
#   OPENCODE_TAG (string): git tag to build from
#   LATEST_VERSION (string): version baked into the binary at build time
#   BUILD_JOBS (int): bun/turbo concurrency
#   CACHE (string): host cache dir; source tree + bun store cached
#   OC_SRC_IMG (string): image name committed when complete
# Outputs:
#   Commits ${OC_SRC_IMG} with /usr/local/bin/opencode
# ---------------------------------------------------------------------------
build_ocbin_source() {
  local container release_tag
  release_tag="${OPENCODE_TAG}"
  container=$(buildah from docker.io/oven/bun:1.3.14-debian)
  buildah config --env HOME=/mnt/host_cache/bun "$container"
  buildah config --env NODE_OPTIONS=--max-old-space-size=4096 "$container"
  buildah run --volume "${CACHE}:/mnt/host_cache" "$container" -- bash -ec "
    set -e
    export HOME=/mnt/host_cache/bun
    mkdir -p /mnt/host_cache/opencode_src
    apt-get update && apt-get install -y --no-install-recommends \
      git curl ca-certificates jq ca-certificates
    cd /mnt/host_cache/opencode_src
    if [ ! -d repo/.git ]; then
      git clone --branch ${release_tag} --depth 1 \\
        https://github.com/anomalyco/opencode.git repo
    else
      cd repo
      git fetch --tags --depth 1 origin ${release_tag}
      git checkout FETCH_HEAD
      cd ..
    fi
    mkdir -p /src/opencode
    cp -r /mnt/host_cache/opencode_src/repo/. /src/opencode/
    cd /src/opencode
    bun install --backend=copyfile --ignore-scripts --network-concurrency=1
    export OPENCODE_VERSION=\"${LATEST_VERSION:-1.18.31}\"
    export OPENCODE_CHANNEL=prod
    export HUSKY=0
    export BUN_CONFIG_MAX_WORKERS=${BUILD_JOBS}
    HUSKY=0 bun run --cwd packages/core fix-node-pty
    bun x turbo run build --filter=opencode --concurrency ${BUILD_JOBS} \\
      --env-mode=loose -- --single
    chmod +x packages/opencode/dist/opencode-linux-x64/bin/opencode
    cp packages/opencode/dist/opencode-linux-x64/bin/opencode /usr/local/bin/opencode
    rm -rf /src/opencode
  "
  buildah commit --rm "$container" "${OC_SRC_IMG}"
}

# ---------------------------------------------------------------------------
# build_ocbin_binary()
#
# Description: layers the pinned upstream opencode release binary onto a
#   scratch rootfs after sha256 VERIFYING it against the release asset
#   digest published by the GitHub API.
# Globals:
#   OPENCODE_TAG (string): release tag whose asset is downloaded
#   RESOLVED_HASH (string): tag hash; names the per-hash DL subdir
#   DL (string): host dir holding downloaded release tarballs
#   OC_BIN_IMG (string): image name committed when complete
# Outputs:
#   Commits ${OC_BIN_IMG} with /usr/local/bin/opencode
# ---------------------------------------------------------------------------
build_ocbin_binary() {
  local release_tag download_dir tarball asset_digest container
  release_tag="${OPENCODE_TAG}"
  download_dir="${DL}/${RESOLVED_HASH}"
  tarball="${download_dir}/opencode-linux-x64.tar.gz"
  mkdir -p "${download_dir}"

  if [ ! -x "${download_dir}/opencode" ]; then
    info "==> Resolving pinned binary release digest (${release_tag})..."
    asset_digest=$(curl -fsSL "https://api.github.com/repos/anomalyco/opencode/releases/tags/${release_tag}" |
      jq -r '.assets[] | select(.name == "opencode-linux-x64.tar.gz") | .digest')
    ok " Digest locked: ${asset_digest}"
    curl -fL --retry 3 -o "${tarball}" \
      "https://github.com/anomalyco/opencode/releases/download/${release_tag}/opencode-linux-x64.tar.gz"
    echo "${asset_digest#sha256:}  ${tarball}" | sha256sum -c -
    tar -xzf "${tarball}" -C "${download_dir}"
    rm -f "${tarball}"
  fi
  chmod +x "${download_dir}/opencode"

  container=$(buildah from scratch)
  buildah copy "$container" "${download_dir}/opencode" /usr/local/bin/opencode
  buildah config --env OPENCODE_BINARY=1 "$container"
  buildah commit --rm "$container" "${OC_BIN_IMG}"
}

# ---------------------------------------------------------------------------
# build_pgassets()
#
# Description: installs the postgres 18 client, dev headers and pgvector
#   (built from source) but stages what the server image needs into
#   /pg-layer/... so compose can cherry-pick the payload
#   (usr/lib/postgresql, usr/share/postgresql, libpq*.so).
# Globals:
#   PGVER (string): pgvector version; drives the git checkout
#   BUILD_JOBS (int): parallelism for the pgvector make
#   CACHE (string): host cache dir; pgvector git checkout cached
#   PGA_IMG (string): image name committed when complete
# Outputs:
#   Commits ${PGA_IMG} with the /pg-layer payload staging tree
# ---------------------------------------------------------------------------
build_pgassets() {
  local container
  container=$(buildah from "${BASE_IMG}")
  buildah run --volume "${CACHE}:/mnt/host_cache" "$container" -- bash -ec "
    set -e
    apt-get update && apt-get install -y --no-install-recommends gnupg lsb-release
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | \
      gpg --dearmor -o /usr/share/keyrings/postgresql.gpg
    printf 'Types: deb\nURIs: https://apt.postgresql.org/pub/repos/apt\nSuites: %s-pgdg\nComponents: main\nSigned-By: /usr/share/keyrings/postgresql.gpg\n' \
      \"\$(lsb_release -cs)\" > /etc/apt/sources.list.d/pgdg.sources
    apt-get update && apt-get install -y --no-install-recommends \
      postgresql-server-dev-18 postgresql-client-18 libpq-dev git make gcc
    cd /tmp
    if [ ! -d /mnt/host_cache/pgvector_src/pgvector-${PGVER} ]; then
      git clone --branch v${PGVER} --depth 1 \
        https://github.com/pgvector/pgvector.git \
        /mnt/host_cache/pgvector_src/pgvector-${PGVER}
    fi
    rm -rf /tmp/pgvector-${PGVER}
    cp -r /mnt/host_cache/pgvector_src/pgvector-${PGVER}/. /tmp/pgvector-${PGVER}/
    cd /tmp/pgvector-${PGVER}
    make -j${BUILD_JOBS}
    make install
    cd /tmp && rm -rf /tmp/pgvector-${PGVER}
  "
  buildah run "$container" -- bash -ec "
    set -e
    mkdir -p /pg-layer/usr/lib/postgresql /pg-layer/usr/share/postgresql
    cp -a /usr/lib/postgresql/. /pg-layer/usr/lib/postgresql/
    cp -a /usr/share/postgresql/. /pg-layer/usr/share/postgresql/
    mkdir -p /pg-layer/usr/lib/x86_64-linux-gnu
    cp -a /usr/lib/x86_64-linux-gnu/libpq* /pg-layer/usr/lib/x86_64-linux-gnu/
  "
  buildah commit --rm "$container" "${PGA_IMG}"
}

# ---------------------------------------------------------------------------
# build_rusttools()
#
# Description: bootstraps rustup inside the container and `cargo install`s
#   lean-ctx into /usr/local/bin. The only layer meant to be rebuilt when
#   lean-ctx upstream moves.
# Globals:
#   BUILD_JOBS (int): CARGO_BUILD_JOBS + --jobs parallelism
#   CACHE (string): host cache dir; apt debs bound at /mnt/host_cache
#   APTDROP (string): apt snippet pinning debs to the host cache
#   RUST_IMG (string): image name committed when complete
# Outputs:
#   Commits ${RUST_IMG} with /usr/local/bin/lean-ctx
# ---------------------------------------------------------------------------
build_rusttools() {
  local container
  container=$(buildah from docker.io/library/debian:trixie-slim)
  buildah config --env DEBIAN_FRONTEND=noninteractive "$container"
  buildah config --env HOME=/root "$container"
  buildah run --volume "${CACHE}:/mnt/host_cache" "$container" -- bash -ec "
    set -e
    mkdir -p /mnt/host_cache/apt_cache/partial
    ${APTDROP}
    apt-get update && apt-get install -y --no-install-recommends \
      build-essential ca-certificates curl git pkg-config libssl-dev
    curl --proto '=https' --tlsv1.3 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
  "
  buildah config --env CARGO_BUILD_JOBS="${BUILD_JOBS}" "$container"
  buildah run "$container" -- bash -ec "
    set -e
    . \$HOME/.cargo/env
    cargo install lean-ctx --root /usr/local --jobs ${BUILD_JOBS}
  "
  buildah commit --rm "$container" "${RUST_IMG}"
}

# ---------------------------------------------------------------------------
# build_uvbin()
#
# Description: strips uv and uvx out of the official astral-sh image and
#   re-layers just those two binaries onto a scratch rootfs so merge_payload
#   can place them arbitrarily.
# Globals:
#   UVBIN_IMG (string): image name committed when complete
# Outputs:
#   Commits ${UVBIN_IMG} containing /uv and /uvx at the rootfs root
# ---------------------------------------------------------------------------
build_uvbin() {
  local source_container container
  source_container=$(buildah from ghcr.io/astral-sh/uv:latest)
  container=$(buildah from scratch)
  buildah copy --from="$source_container" "$container" /uv /uvx /
  buildah rm "$source_container"
  buildah commit --rm "$container" "${UVBIN_IMG}"
}

# ---------------------------------------------------------------------------
# build_mcp()
#
# Description: pre-installs the MCP/LSP tool payload into
#   /home/opencode/.local (uv tools + global npm packages) as the opencode
#   user; the whole .local tree is later merged into composed servers.
#   Includes: semble[mcp], code-index-mcp, python-lsp-server, repomix,
#   bash-language-server. Declares the uv tool/npm prefix env the tools need.
# Globals:
#   CACHE (string): host cache dir; apt debs bound at /mnt/host_cache
#   MCP_IMG (string): image name committed when complete
# Outputs:
#   Commits ${MCP_IMG} with the populated /home/opencode/.local
# ---------------------------------------------------------------------------
build_mcp() {
  local uv_container container
  container=$(buildah from "${BASE_IMG}")
  uv_container=$(buildah from "${UVBIN_IMG}")
  buildah copy --from="$uv_container" "$container" /uv /uvx /bin/
  buildah rm "$uv_container"
  buildah config --env HOME=/home/opencode "$container"
  buildah config --env UV_TOOL_DIR=/home/opencode/.local/share/uv/tools "$container"
  buildah config --env UV_TOOL_BIN_DIR=/home/opencode/.local/bin "$container"
  buildah config --env NPM_CONFIG_PREFIX=/home/opencode/.local "$container"
  buildah run --volume "${CACHE}:/mnt/host_cache" --user opencode "$container" -- bash -ec '
    set -e
    uv tool install --with mcp "semble[mcp]"
    uv tool install "code-index-mcp"
    uv tool install "python-lsp-server"
    npm install -g \
      --registry=https://registry.npmjs.org \
      --network-concurrency=8 \
      --fetch-retry-maxtimeout=300000 \
      --fetch-timeout=300000 \
      repomix bash-language-server
    rm -rf /home/opencode/.npm /home/opencode/.cache
  '
  buildah commit --rm "$container" "${MCP_IMG}"
}

# ---------------------------------------------------------------------------
# merge_payload(<container>, <layer_image>, <source_rootfs_path>, <target_rootfs_path>)
#
# Description: layers a subtree from a committed layer image into a working
#   container using cp -a semantics, preserving ownership/permissions.
#   Both rootfs trees are buildah-mounted to the host, the payload is copied
#   root-first (a trailing '/' on <target_rootfs_path> means "into that dir").
#   A trailing "/." on <source_rootfs_path> requests CONTENTS-merge into an
#   existing target directory (cp -a of a <dir>/ onto an existing <dir>/
#   nests a subdirectory instead of merging the entries).
# Args:
#   $1  container (string): working container to receive the files
#   $2  layer_image (string): image the payload comes from
#   $3  source_rootfs_path (string): path inside <layer_image> rootfs
#   $4  target_rootfs_path (string): destination path inside <container> rootfs
# Outputs:
#   None directly; the <container> filesystem is modified and the temporary
#   source container is removed
# ---------------------------------------------------------------------------
merge_payload() {
  local container="$1" layer_image="$2" source_rootfs_path="$3" target_rootfs_path="$4"
  local source_container source_rootfs target_rootfs
  source_container=$(buildah from "$layer_image")
  source_rootfs=$(buildah mount "$source_container")
  target_rootfs=$(buildah mount "$container")
  mkdir -p "$(dirname "${target_rootfs}${target_rootfs_path}")"
  cp -a "${source_rootfs}${source_rootfs_path}" "${target_rootfs}${target_rootfs_path}"
  buildah umount "$container"
  buildah umount "$source_container"
  buildah rm "$source_container"
}

# ---------------------------------------------------------------------------
# compose_server(<stack>, <src>, <tail>)
#
# Description: assembles the opencode-server image by picking layers per
#   the variant. full picks pydex (python PATH prefix), pgassets, rusttools;
#   basic starts from base. Both merge ocbin, uvbin and the mcp payload,
#   bake the opencode.json (lean_ctx only for full), normalise /home/opencode
#   ownership (chown HOST_UID:0, then chmod g=u), and set user/workdir/
#   entrypoint before committing. tail controls the local tag: empty ->
#   latest + <version>,
#   otherwise a distinct <tail> + <tail>-<version>.
# Args:
#   $1  stack (string): "full" or "basic"
#   $2  src (string): "source" or "binary"
#   $3  tail (string): "" (default variant) or a suffix like "basic",
#       "full-binary", "basic-binary"
# Globals:
#   PYVER (string): /opt/python-<PYVER> PATH prefix for full stacks
#   SERVER_IMG (string): namespace of the committed image
#   LATEST_VERSION (string): version tag suffix
#   STAGE (string): scratch dir holding the stripped -basic config
# Outputs:
#   Commits ${SERVER_IMG}:latest (or :<tail>) + version tag; prints ok
# ---------------------------------------------------------------------------
compose_server() {
  local stack="$1" src="$2" tail="$3" container ocbin_image python_path_prefix config_source
  config_source="${REPO_ROOT}/build/opencode/opencode.jsonc"
  if [ "${stack}" = full ]; then
    container=$(buildah from "${PYDEX_IMG}")
    python_path_prefix="/opt/python-${PYVER}/bin:"
  else
    container=$(buildah from "${BASE_IMG}")
    python_path_prefix=""
  fi
  ocbin_image=$(ocbin_for "$src")

  merge_payload "$container" "$ocbin_image" /usr/local/bin/opencode /usr/local/bin/opencode
  merge_payload "$container" "${UVBIN_IMG}" /uv /bin/uv
  merge_payload "$container" "${UVBIN_IMG}" /uvx /bin/uvx
  merge_payload "$container" "${MCP_IMG}" /home/opencode/.local /home/opencode/
  if [ "${stack}" = full ]; then
    merge_payload "$container" "${PGA_IMG}" /pg-layer/usr/lib/postgresql /usr/lib/postgresql
    merge_payload "$container" "${PGA_IMG}" /pg-layer/usr/share/postgresql /usr/share/postgresql
    merge_payload "$container" "${PGA_IMG}" /pg-layer/usr/lib/x86_64-linux-gnu/. /usr/lib/x86_64-linux-gnu/
    merge_payload "$container" "${RUST_IMG}" /usr/local/bin/lean-ctx /usr/local/bin/lean-ctx
  fi

  buildah config --env HOME=/home/opencode "$container"
  buildah config --env NPM_CONFIG_PREFIX=/home/opencode/.local "$container"
  buildah config --env UV_TOOL_DIR=/home/opencode/.local/share/uv/tools "$container"
  buildah config --env UV_TOOL_BIN_DIR=/home/opencode/.local/bin "$container"
  buildah config --env PATH="${python_path_prefix}/home/opencode/.local/bin:/usr/local/bin:/usr/bin:/bin" "$container"

  # opencode.jsonc is the full-stack config; basic drops the lean_ctx entry
  if [ "${stack}" = full ]; then
    buildah copy "$container" "${config_source}" /home/opencode/.config/opencode/opencode.json
  else
    jq 'del(.mcp.lean_ctx)' "${config_source}" >"${STAGE}/opencode-basic.json"
    buildah copy "$container" "${STAGE}/opencode-basic.json" /home/opencode/.config/opencode/opencode.json
  fi
  buildah run "$container" -- bash -ec "
    mkdir -p /home/opencode/.local/share/opencode /home/opencode/.local/state/opencode \
      /home/opencode/.cache/opencode /home/opencode/.npm
    chown -R ${HOST_UID}:0 /home/opencode
    chmod -R g=u /home/opencode
    # uid-agnostic runtime state: the fortress may run the container with
    # --userns keep-id + --user <invoking-host-uid>, which differs from the
    # bake-time HOST_UID on other hosts (e.g. 60139 on a systemd-homed box).
    # Traverse/exec for every identity across home, plus world-write on the
    # mutable XDG/workspace dirs so any identity can create state; binary
    # execute bits under .local are preserved (X only adds x to dirs).
    chmod -R o+X /home/opencode
    chmod -R o+rwX /home/opencode/.local/share/opencode /home/opencode/.local/state/opencode \
      /home/opencode/.cache/opencode /home/opencode/.config/opencode /home/opencode/workspace \
      /home/opencode/.npm
  "
  buildah config --user opencode "$container"
  buildah config --workingdir /home/opencode/workspace "$container"
  buildah config --entrypoint '["opencode"]' "$container"

  if [ -z "${tail}" ]; then
    buildah commit --rm "$container" "${SERVER_IMG}:latest"
    buildah tag "${SERVER_IMG}:latest" "${SERVER_IMG}:${LATEST_VERSION}"
  else
    buildah commit --rm "$container" "${SERVER_IMG}:${tail}"
    buildah tag "${SERVER_IMG}:${tail}" "${SERVER_IMG}:${tail}-${LATEST_VERSION}"
  fi
  ok " Server image ready: ${SERVER_IMG}:${tail:-latest}"
}

# ---------------------------------------------------------------------------
# compose_tui(<src>, <tail>)
#
# Description: assembles the slim attach-only opencode-tui image: tui-base +
#   the ocbin binary, xdg state dirs, and opencode as entrypoint.
# Args:
#   $1  src (string): "source" or "binary"
#   $2  tail (string): "" (default variant) or a suffix for variant-distinct
#       tags like "basic"/"full-binary"/"basic-binary"
# Globals:
#   TUI_IMG (string): namespace of the committed image
#   LATEST_VERSION (string): version tag suffix
# Outputs:
#   Commits ${TUI_IMG}:latest (or :<tail>) + version tag
# ---------------------------------------------------------------------------
compose_tui() {
  local src="$1" tail="$2" container ocbin_image
  container=$(buildah from "${TUI_BASE_IMG}")
  ocbin_image=$(ocbin_for "$src")
  merge_payload "$container" "$ocbin_image" /usr/local/bin/opencode /usr/local/bin/opencode

  buildah config --env HOME=/home/opencode "$container"
  buildah config --env PATH=/usr/local/bin:/usr/bin:/bin "$container"
  buildah run --user opencode "$container" -- bash -ec '
    mkdir -p /home/opencode/workspace /home/opencode/.cache/opencode \
      /home/opencode/.local/share/opencode /home/opencode/.local/state/opencode \
      /home/opencode/.npm
    chmod -R o+X /home/opencode
    chmod -R o+rwX /home/opencode/workspace /home/opencode/.cache/opencode \
      /home/opencode/.local/share/opencode /home/opencode/.local/state/opencode \
      /home/opencode/.npm
  '
  buildah config --user opencode "$container"
  buildah config --workingdir /home/opencode/workspace "$container"
  buildah config --entrypoint '["opencode"]' "$container"

  if [ -z "${tail}" ]; then
    buildah commit --rm "$container" "${TUI_IMG}:latest"
    buildah tag "${TUI_IMG}:latest" "${TUI_IMG}:${LATEST_VERSION}"
  else
    buildah commit --rm "$container" "${TUI_IMG}:${tail}"
    buildah tag "${TUI_IMG}:${tail}" "${TUI_IMG}:${tail}-${LATEST_VERSION}"
  fi
  ok " TUI image ready: ${TUI_IMG}:${tail:-latest}"
}

# ---------------------------------------------------------------------------
# ensure_all_layers(<stack>, <src>)
#
# Description: orders ensure() over every layer a variant needs. The cheap
#   layers are shared by both stacks; the heavy three (pydex, rusttools,
#   pgassets) only build when the stack is full.
# Args:
#   $1  stack (string): "full" or "basic"
#   $2  src (string): "source" or "binary"
# Outputs:
#   Side effect of ensure(): each required layer image present locally/pushed
# ---------------------------------------------------------------------------
ensure_all_layers() {
  local stack="$1" src="$2"
  ensure base "${BASE_IMG}"
  ensure tui_base "${TUI_BASE_IMG}"
  ensure uvbin "${UVBIN_IMG}"
  ensure mcp "${MCP_IMG}"
  if [ "${stack}" = full ]; then
    ensure pydex "${PYDEX_IMG}"
    ensure rusttools "${RUST_IMG}"
    ensure pgassets "${PGA_IMG}"
  fi
  ensure "ocbin_${src}" "$(ocbin_for "$src")"
}

# ---------------------------------------------------------------------------
# usage()
#
# Description: prints the valid subcommands and variant env knobs.
# Outputs:
#   Usage text to stderr
# Returns:
#   Exits 2 (usage error)
# ---------------------------------------------------------------------------
usage() {
  echo "usage: buildah-build.sh <layers|server|tui|build>" >&2
  echo "         STACK=full|basic  SRC=source|binary  TAIL=full-binary|basic|basic-binary" >&2
  exit 2
}

# ---------------------------------------------------------------------------
# Dispatch
#   layers  - ensure all layer images for the variant (build + push missing)
#   server  - compose the opencode-server image only
#   tui     - compose the opencode-tui image only
#   build   - layers, then compose both finals (the publish path)
# ---------------------------------------------------------------------------
case "${1:-}" in
layers)
  ensure_all_layers "${STACK:-full}" "${SRC:-source}"
  ;;
server)
  compose_server "${STACK:-full}" "${SRC:-source}" "${TAIL:-}"
  ;;
tui)
  compose_tui "${SRC:-source}" "${TAIL:-}"
  ;;
build)
  ensure_all_layers "${STACK:-full}" "${SRC:-source}"
  compose_server "${STACK:-full}" "${SRC:-source}" "${TAIL:-}"
  compose_tui "${SRC:-source}" "${TAIL:-}"
  ;;
*)
  usage
  ;;
esac
