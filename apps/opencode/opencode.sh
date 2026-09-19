#!/bin/sh
set -e

REPO_ROOT=$(CDPATH= cd "$(dirname "$0")/../.." && pwd)
. "${REPO_ROOT}/lib/cli.sh"

COMPILER_IMG="${REG_URL}/library/opencode/opencode-compiler"
SERVER_IMG="${REG_URL}/library/opencode/opencode-server"
TUI_IMG="${REG_URL}/library/opencode/opencode-tui"
CACHE_DIR="${REPO_ROOT}/build/opencode/cache"

resolve_version() {
  if [ -z "${LATEST_VERSION:-}" ]; then
    info "==> Querying upstream repository for latest stable release tag..."
    LATEST_VERSION=$(curl -s "https://api.github.com/repos/anomalyco/opencode/releases/latest" |
      jq -r .tag_name | sed 's/^v//' || true)

    if [ -z "$LATEST_VERSION" ]; then
      warn " Could not fetch dynamic tags. Falling back to core engine default baseline..."
      LATEST_VERSION="1.17.0"
    else
      ok " Found current production release version: ${LATEST_VERSION}"
    fi
  fi

  if [ -z "${RESOLVED_HASH:-}" ]; then
    resolved_tag="${OPENCODE_TAG:-v${LATEST_VERSION}}"
    RESOLVED_HASH=$(git ls-remote "https://github.com/anomalyco/opencode.git" "refs/tags/${resolved_tag}^{}" 2>/dev/null | cut -c1-7 || true)
    if [ -z "${RESOLVED_HASH}" ]; then
      RESOLVED_HASH=$(git ls-remote "https://github.com/anomalyco/opencode.git" "refs/tags/${resolved_tag}" 2>/dev/null | cut -c1-7 || true)
    fi
    if [ -z "${RESOLVED_HASH}" ]; then
      RESOLVED_HASH=$(git ls-remote "https://github.com/anomalyco/opencode.git" HEAD 2>/dev/null | cut -c1-7 || true)
    fi
    if [ -n "${RESOLVED_HASH}" ]; then
      ok " Locked hash for tag ${resolved_tag}: ${RESOLVED_HASH}"
    else
      warn " Could not resolve tag hash for ${resolved_tag}; leaving to compiler–runtime baseline..."
    fi
  fi
  export LATEST_VERSION RESOLVED_HASH
}

build_compiler() {
  mkdir -p "${CACHE_DIR}"/{apt_cache/partial,python_src,opencode_src,pgvector_src,bun,cargo}
  resolve_version

  info "==> Compiling Opencode Source Assets..."
  podman build -f "${REPO_ROOT}/build/opencode/Build.Containerfile" \
    --build-arg RESOLVED_VERSION="${LATEST_VERSION}" \
    --build-arg OPENCODE_TAG="${OPENCODE_TAG:-v${LATEST_VERSION}}" \
    --build-arg OPENCODE_SOURCE="${OPENCODE_SOURCE:-source}" \
    -v "${CACHE_DIR}:/mnt/host_cache:z" \
    -t "${COMPILER_IMG}:latest" \
    -t "${COMPILER_IMG}:${LATEST_VERSION}" \
    "${REPO_ROOT}"
}

build_runtime() {
  _target="$1"
  _image="$2"
  resolve_version

  case "${_target}" in
    runner) info "==> Assembling production Opencode Server layer..." ;;
    tui) info "==> Extracting compiled assets into slim TUI client..." ;;
  esac

  podman build -f "${REPO_ROOT}/build/opencode/Runtime.Containerfile" \
    --target "${_target}" \
    --network host \
    --build-arg COMPILER_IMAGE="${COMPILER_IMG}:${LATEST_VERSION}" \
    --build-arg HOST_UID="${HOST_UID}" \
    --build-arg HOST_GID="${HOST_GID}" \
    -v "${CACHE_DIR}:/mnt/host_cache:z" \
    -t "${_image}:latest" \
    -t "${_image}:${LATEST_VERSION}" \
    "${REPO_ROOT}"
}

distribute_images() {
  if [ -z "${RESOLVED_HASH:-}" ]; then
    error "Cannot distribute: could not resolve release tag hash."
    exit 1
  fi
  warn "==> Distributing Opencode [${RESOLVED_HASH}] container imagery..."

  podman tag "${COMPILER_IMG}:latest" "${COMPILER_IMG}:${RESOLVED_HASH}"
  podman tag "${SERVER_IMG}:latest" "${SERVER_IMG}:${RESOLVED_HASH}"
  podman tag "${TUI_IMG}:latest" "${TUI_IMG}:${RESOLVED_HASH}"

  podman push "${COMPILER_IMG}:latest"
  podman push "${COMPILER_IMG}:${LATEST_VERSION}"
  podman push "${COMPILER_IMG}:${RESOLVED_HASH}"

  podman push "${SERVER_IMG}:latest"
  podman push "${SERVER_IMG}:${LATEST_VERSION}"
  podman push "${SERVER_IMG}:${RESOLVED_HASH}"

  podman push "${TUI_IMG}:latest"
  podman push "${TUI_IMG}:${LATEST_VERSION}"
  podman push "${TUI_IMG}:${RESOLVED_HASH}"

  ok "✔ Opencode distribution loop completed!"
}

case "$1" in
compiler)
  build_compiler
  ;;

server)
  build_runtime runner "${SERVER_IMG}"
  ;;

tui)
  build_runtime tui "${TUI_IMG}"
  ;;

publish)
  case "${2:-}" in
    ""|binary) ;;
    *)
      error "Error: Unknown publish variant '$2' (expected binary)."
      exit 1
      ;;
  esac

  if [ "${2:-}" = "binary" ]; then
    info "==> Validating pinned binary Opencode release artifact signature..."
    OPENCODE_SOURCE="binary"
    OPENCODE_TAG="${OPENCODE_TAG:-v1.18.31}"
    export OPENCODE_SOURCE OPENCODE_TAG
  fi

  unset LATEST_VERSION RESOLVED_HASH 2>/dev/null || true
  build_compiler
  build_runtime runner "${SERVER_IMG}"
  build_runtime tui "${TUI_IMG}"
  distribute_images
  ;;

clean)
  warn "==> Dismantling Opencode execution runtimes and heavy compiler tracking layers..."
  podman rm -f ai-jail-opencode ai-jail-shell 2>/dev/null || true

  podman rmi $(podman images -q "${SERVER_IMG}") 2>/dev/null || true
  podman rmi $(podman images -q "${TUI_IMG}") 2>/dev/null || true
  podman rmi $(podman images -q "${COMPILER_IMG}") 2>/dev/null || true
  ok "✔ Opencode dismantling cycle completed safely."
  ;;

*)
  error "Error: Unknown opencode action target."
  exit 1
  ;;
esac