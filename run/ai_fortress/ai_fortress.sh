#!/bin/sh
set -e

# 1. Boot up our shared coloring engine from the central library folder (Updated to Singular)
. "${CONTAINER_REPO_PATH}/lib/colors.sh"

COMPILER_IMG="${REG_URL}/opencode-compiler:latest"
SERVER_IMG="${REG_URL}/opencode-server:latest"
TUI_IMG="${REG_URL}/opencode-tui:latest"
GOOSE_SERVER_IMG="${REG_URL}/goose-server:latest"
GOOSE_CLI_IMG="${REG_URL}/goose-cli:latest"

case "$1" in
# ── Opencode Actions ──
build-compiler)
  info "==> Checking remote GitHub tracking layers..."
  mkdir -p "${CONTAINER_REPO_PATH}/build/opencode/cache"
  git ls-remote https://github.com/anomalyco/opencode.git HEAD | awk '{print $1}' >"${CONTAINER_REPO_PATH}/build/opencode/cache/latest_commit.txt"
  info "==> Compiling Opencode Source Assets..."
  podman build -f "${CONTAINER_REPO_PATH}/build/opencode/Build.Containerfile" \
    -t "${COMPILER_IMG}" "${CONTAINER_REPO_PATH}"
  ;;

build-server)
  info "==> Assembling production Opencode Server layer..."
  podman build -f "${CONTAINER_REPO_PATH}/build/opencode/Runtime.Containerfile" \
    --target runner \
    --build-arg COMPILER_IMAGE="${COMPILER_IMG}" \
    --build-arg HOST_UID="${HOST_UID}" \
    --build-arg HOST_GID="${HOST_GID}" \
    -v "${CONTAINER_REPO_PATH}/build/opencode/cache:/mnt/host_cache:z" \
    -t "${SERVER_IMG}" "${CONTAINER_REPO_PATH}"
  ;;

build-tui)
  info "==> Extracting compiled assets into slim TUI client..."
  podman build -f "${CONTAINER_REPO_PATH}/build/opencode/Runtime.Containerfile" \
    --target tui \
    --build-arg COMPILER_IMAGE="${COMPILER_IMG}" \
    --build-arg HOST_UID="${HOST_UID}" \
    --build-arg HOST_GID="${HOST_GID}" \
    -v "${CONTAINER_REPO_PATH}/build/opencode/cache:/mnt/host_cache:z" \
    -t "${TUI_IMG}" "${CONTAINER_REPO_PATH}"
  ;;

publish-opencode)
  "$0" build-server
  "$0" build-tui
  _hash=$(git ls-remote https://github.com/anomalyco/opencode.git HEAD | cut -c1-7)
  warn "==> Distributing Opencode [${_hash}] container imagery..."

  # Tag the local build with the git hash
  podman tag "${SERVER_IMG}" "${REG_URL}/opencode-server:${_hash}"
  podman tag "${TUI_IMG}" "${REG_URL}/opencode-tui:${_hash}"

  # Push both the hash tags and the latest tags
  podman push "${SERVER_IMG}"
  podman push "${TUI_IMG}"
  podman push "${REG_URL}/opencode-server:${_hash}"
  podman push "${REG_URL}/opencode-tui:${_hash}"
  ok "✔ Opencode distribution loop completed!"
  ;;

clean-opencode)
  warn "==> Dismantling Opencode execution runtimes..."
  podman rm -f ai-jail-opencode ai-jail-shell 2>/dev/null || true
  podman image rm "${SERVER_IMG}" "${TUI_IMG}" 2>/dev/null || true
  ;;

# ── Goose Actions ──
build-goose-server)
  info "==> Building centralized Goose AI Server..."
  podman build -f "${CONTAINER_REPO_PATH}/build/goose/Containerfile" \
    --target goose-server \
    --build-arg HOST_UID="${HOST_UID}" \
    --build-arg HOST_GID="${HOST_GID}" \
    -t "${GOOSE_SERVER_IMG}" "${CONTAINER_REPO_PATH}"
  ;;

build-goose-cli)
  info "==> Building interactive terminal Goose CLI..."
  podman build -f "${CONTAINER_REPO_PATH}/build/goose/Containerfile" \
    --target goose-cli \
    --build-arg HOST_UID="${HOST_UID}" \
    --build-arg HOST_GID="${HOST_GID}" \
    -t "${GOOSE_CLI_IMG}" "${CONTAINER_REPO_PATH}"
  ;;

publish-goose)
  "$0" build-goose-server
  "$0" build-goose-cli
  _hash=$(git ls-remote https://github.com/aaif-goose/goose.git HEAD | cut -c1-7)
  warn "==> Distributing Goose [${_hash}] container imagery..."

  # Tag the local build with the git hash
  podman tag "${GOOSE_SERVER_IMG}" "${REG_URL}/goose-server:${_hash}"
  podman tag "${GOOSE_CLI_IMG}" "${REG_URL}/goose-cli:${_hash}"

  # Push both the hash tags and the latest tags
  podman push "${GOOSE_SERVER_IMG}"
  podman push "${GOOSE_CLI_IMG}"
  podman push "${REG_URL}/goose-server:${_hash}"
  podman push "${REG_URL}/goose-cli:${_hash}"
  ok "✔ Goose distribution loop completed!"
  ;;

clean-goose)
  warn "==> Dismantling Goose execution runtimes..."
  podman rm -f ai-jail-goose ai-jail-goose-shell 2>/dev/null || true
  podman image rm "${GOOSE_SERVER_IMG}" "${GOOSE_CLI_IMG}" 2>/dev/null || true
  ;;

*)
  error "Error: Unknown fortress action target."
  exit 1
  ;;
esac
