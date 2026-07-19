#!/bin/sh
set -e

. "${CONTAINER_REPO_PATH}/lib/colors.sh"

SNAPCLIENT_IMG="localhost/snapclient:latest"

case "$1" in
build)
  info "==> Building Snapcast client container..."
  podman build -f "${CONTAINER_REPO_PATH}/build/snapclient/Dockerfile" \
    -t "${SNAPCLIENT_IMG}" "${CONTAINER_REPO_PATH}/build/snapclient"
  ;;

clean)
  warn "==> Removing Snapclient image..."
  podman image rm "${SNAPCLIENT_IMG}" 2>/dev/null || true
  ;;

*)
  error "Error: Unknown snapclient action. Use build or clean."
  exit 1
  ;;
esac
