#!/bin/sh
set -e

# 1. Boot up our shared coloring engine from the central library folder (Updated to Singular)
. "${CONTAINER_REPO_PATH}/lib/colors.sh"

COMPILER_IMG="${REG_URL}/library/opencode/opencode-compiler"
SERVER_IMG="${REG_URL}/library/opencode/opencode-server"
TUI_IMG="${REG_URL}/library/opencode/opencode-tui"
GOOSE_SERVER_IMG="${REG_URL}/library/goose/goose-server"
GOOSE_CLI_IMG="${REG_URL}/library/goose/goose-cli"

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
}

case "$1" in
# ── Opencode Actions ──
build-compiler)
  info "==> Checking remote GitHub tracking layers..."
  mkdir -p "${CONTAINER_REPO_PATH}/build/opencode/cache"/{apt_cache/partial,python_src,opencode_src,pgvector_src,bun,cargo}
  git ls-remote https://github.com/anomalyco/opencode.git HEAD | awk '{print $1}' >"${CONTAINER_REPO_PATH}/build/opencode/cache/latest_commit.txt"

  resolve_version

  info "==> Compiling Opencode Source Assets..."
  podman build -f "${CONTAINER_REPO_PATH}/build/opencode/Build.Containerfile" \
    --build-arg RESOLVED_VERSION="${LATEST_VERSION}" \
    --build-arg OPENCODE_TAG="v${LATEST_VERSION}" \
    -v "${CONTAINER_REPO_PATH}/build/opencode/cache:/mnt/host_cache:z" \
    -t "${COMPILER_IMG}:latest" \
    -t "${COMPILER_IMG}:${LATEST_VERSION}" \
    "${CONTAINER_REPO_PATH}"
  ;;

build-server)
  resolve_version
  info "==> Assembling production Opencode Server layer..."
  podman build -f "${CONTAINER_REPO_PATH}/build/opencode/Runtime.Containerfile" \
    --target runner \
    --network host \
    --build-arg COMPILER_IMAGE="${COMPILER_IMG}:${LATEST_VERSION}" \
    --build-arg HOST_UID="${HOST_UID}" \
    --build-arg HOST_GID="${HOST_GID}" \
    -v "${CONTAINER_REPO_PATH}/build/opencode/cache:/mnt/host_cache:z" \
    -t "${SERVER_IMG}:latest" \
    -t "${SERVER_IMG}:${LATEST_VERSION}" \
    "${CONTAINER_REPO_PATH}"
  ;;

build-tui)
  resolve_version
  info "==> Extracting compiled assets into slim TUI client..."
  podman build -f "${CONTAINER_REPO_PATH}/build/opencode/Runtime.Containerfile" \
    --target tui \
    --build-arg COMPILER_IMAGE="${COMPILER_IMG}:${LATEST_VERSION}" \
    --build-arg HOST_UID="${HOST_UID}" \
    --build-arg HOST_GID="${HOST_GID}" \
    -v "${CONTAINER_REPO_PATH}/build/opencode/cache:/mnt/host_cache:z" \
    -t "${TUI_IMG}:latest" \
    -t "${TUI_IMG}:${LATEST_VERSION}" \
    "${CONTAINER_REPO_PATH}"
  ;;

opencode-publish)
  "$0" build-compiler
  "$0" build-server
  "$0" build-tui
  _hash=$(git ls-remote https://github.com/anomalyco/opencode.git HEAD | cut -c1-7)
  warn "==> Distributing Opencode [${_hash}] container imagery..."

  podman tag "${COMPILER_IMG}:latest" "${COMPILER_IMG}:${_hash}"
  podman tag "${SERVER_IMG}:latest" "${SERVER_IMG}:${_hash}"
  podman tag "${TUI_IMG}:latest" "${TUI_IMG}:${_hash}"

  resolve_version
  podman push "${COMPILER_IMG}:latest"
  podman push "${COMPILER_IMG}:${LATEST_VERSION}"
  podman push "${COMPILER_IMG}:${_hash}"

  podman push "${SERVER_IMG}:latest"
  podman push "${SERVER_IMG}:${LATEST_VERSION}"
  podman push "${SERVER_IMG}:${_hash}"

  podman push "${TUI_IMG}:latest"
  podman push "${TUI_IMG}:${LATEST_VERSION}"
  podman push "${TUI_IMG}:${_hash}"

  ok "✔ Opencode distribution loop completed!"
  ;;

clean-opencode)
  warn "==> Dismantling Opencode execution runtimes and heavy compiler tracking layers..."
  podman rm -f ai-jail-opencode ai-jail-shell 2>/dev/null || true

  podman rmi $(podman images -q "${SERVER_IMG}") 2>/dev/null || true
  podman rmi $(podman images -q "${TUI_IMG}") 2>/dev/null || true
  podman rmi $(podman images -q "${COMPILER_IMG}") 2>/dev/null || true
  ok "✔ Opencode dismantling cycle completed safely."
  ;;

build-goose-server)
  info "==> Building centralized Goose AI Server..."
  podman build -f "${CONTAINER_REPO_PATH}/build/goose/Containerfile" \
    --target goose-server \
    --build-arg HOST_UID="${HOST_UID}" \
    --build-arg HOST_GID="${HOST_GID}" \
    -t "${GOOSE_SERVER_IMG}:latest" "${CONTAINER_REPO_PATH}"
  ;;

build-goose-cli)
  info "==> Building interactive terminal Goose CLI..."
  podman build -f "${CONTAINER_REPO_PATH}/build/goose/Containerfile" \
    --target goose-cli \
    --build-arg HOST_UID="${HOST_UID}" \
    --build-arg HOST_GID="${HOST_GID}" \
    -t "${GOOSE_CLI_IMG}:latest" "${CONTAINER_REPO_PATH}"
  ;;

goose-publish)
  "$0" build-goose-server
  "$0" build-goose-cli
  _hash=$(git ls-remote https://github.com/aaif-goose/goose.git HEAD | cut -c1-7)
  warn "==> Distributing Goose [${_hash}] container imagery..."

  podman tag "${GOOSE_SERVER_IMG}:latest" "${GOOSE_SERVER_IMG}:${_hash}"
  podman tag "${GOOSE_CLI_IMG}:latest" "${GOOSE_CLI_IMG}:${_hash}"

  podman push "${GOOSE_SERVER_IMG}:latest"
  podman push "${GOOSE_SERVER_IMG}:${_hash}"
  podman push "${GOOSE_CLI_IMG}:latest"
  podman push "${GOOSE_CLI_IMG}:${_hash}"
  ok "✔ Goose distribution loop completed!"
  ;;

clean-goose)
  warn "==> Dismantling Goose execution runtimes and localized containers..."
  podman rm -f ai-jail-goose ai-jail-goose-shell 2>/dev/null || true

  podman rmi $(podman images -q "${GOOSE_SERVER_IMG}") 2>/dev/null || true
  podman rmi $(podman images -q "${GOOSE_CLI_IMG}") 2>/dev/null || true
  ok "✔ Goose dismantling cycle completed safely."
  ;;

*)
  error "Error: Unknown fortress action target."
  exit 1
  ;;
esac
