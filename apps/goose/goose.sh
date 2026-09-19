#!/bin/sh
set -e

REPO_ROOT=$(CDPATH= cd "$(dirname "$0")/../.." && pwd)
. "${REPO_ROOT}/lib/cli.sh"

GOOSE_SERVER_IMG="${REG_URL}/library/goose/goose-server"
GOOSE_CLI_IMG="${REG_URL}/library/goose/goose-cli"

case "$1" in
server)
  info "==> Building centralized Goose AI Server..."
  podman build -f "${REPO_ROOT}/build/goose/Containerfile" \
    --target goose-server \
    --build-arg HOST_UID="${HOST_UID}" \
    --build-arg HOST_GID="${HOST_GID}" \
    -t "${GOOSE_SERVER_IMG}:latest" "${REPO_ROOT}"
  ;;

cli)
  info "==> Building interactive terminal Goose CLI..."
  podman build -f "${REPO_ROOT}/build/goose/Containerfile" \
    --target goose-cli \
    --build-arg HOST_UID="${HOST_UID}" \
    --build-arg HOST_GID="${HOST_GID}" \
    -t "${GOOSE_CLI_IMG}:latest" "${REPO_ROOT}"
  ;;

publish)
  "$0" server
  "$0" cli
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

clean)
  warn "==> Dismantling Goose execution runtimes and localized containers..."
  podman rm -f ai-jail-goose ai-jail-goose-shell 2>/dev/null || true

  podman rmi $(podman images -q "${GOOSE_SERVER_IMG}") 2>/dev/null || true
  podman rmi $(podman images -q "${GOOSE_CLI_IMG}") 2>/dev/null || true
  ok "✔ Goose dismantling cycle completed safely."
  ;;

*)
  error "Error: Unknown goose action target."
  exit 1
  ;;
esac