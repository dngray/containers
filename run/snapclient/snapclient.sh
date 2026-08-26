#!/bin/sh
set -e

. "${CONTAINER_REPO_PATH}/lib/colors.sh"

SNAPCLIENT_IMG="${REG_URL:-localhost}/library/snapclient:latest"
PUBLISH_IMG="${REG_URL}/library/snapclient:latest"

case "$1" in
build)
  info "==> Building Snapcast client container..."
  podman build -f "${CONTAINER_REPO_PATH}/build/snapclient/Dockerfile" \
    -t "${SNAPCLIENT_IMG}" "${CONTAINER_REPO_PATH}/build/snapclient"
  ;;

publish)
  "$0" build

  warn "==> Distributing Snapclient container imagery..."
  podman tag "${SNAPCLIENT_IMG}" "${PUBLISH_IMG}"
  podman push "${PUBLISH_IMG}"
  ok "✔ Snapclient distribution loop completed!"
  ;;

clean)
  warn "==> Removing Snapclient image..."
  podman image rm "${SNAPCLIENT_IMG}" 2>/dev/null || true
  ;;

*)
  error "Error: Unknown snapclient action. Use build, publish, or clean."
  exit 1
  ;;
esac
