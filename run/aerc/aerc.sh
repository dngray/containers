#!/bin/sh
set -e

# Pull colors from the central repository library folder
# shellcheck source=lib/colors.sh
. "${CONTAINER_REPO_PATH}/lib/colors.sh"

UI_TAG="aerc-ui:latest"
SYNC_TAG="mail-sync:latest"

case "$1" in
build)
  info "==> Querying upstream repository for latest stable release tag..."

  LATEST_VERSION=$(curl -s "https://git.sr.ht/~rjarry/aerc/refs" |
    grep -Eoi 'href="/~rjarry/aerc/archive/[0-9.]+\.tar\.gz"' |
    grep -oP 'archive/\K[0-9.]*[0-9]' | head -n 1 || true)

  if [ -z "$LATEST_VERSION" ]; then
    warn "Could not fetch dynamic tags. Falling back to core engine default..."
    LATEST_VERSION="0.21.0"
  else
    ok "Found current production release layer version: ${LATEST_VERSION}"
  fi

  info "==> 1/2 Building Interactive UI Client (${UI_TAG})..."
  podman build -f "${CONTAINER_REPO_PATH}/build/aerc-ui/Containerfile" \
    --build-arg LANG=en_US.UTF-8 \
    --build-arg HOST_UID="${HOST_UID}" \
    --build-arg HOST_GID="${HOST_GID}" \
    --build-arg version="${LATEST_VERSION}" \
    -t "${UI_TAG}" "${CONTAINER_REPO_PATH}"

  info "==> 2/2 Building Headless Sync Automation Daemon (${SYNC_TAG})..."
  podman build -f "${CONTAINER_REPO_PATH}/build/mail-sync/Containerfile" \
    --build-arg HOST_UID="${HOST_UID}" \
    --build-arg HOST_GID="${HOST_GID}" \
    -t "${SYNC_TAG}" "${CONTAINER_REPO_PATH}"
  ;;

clean)
  warn "🧹 Purging old Aerc container components and split image assets..."
  podman rm -f aerc-ui aerc-sync 2>/dev/null || true
  podman image rm "${UI_TAG}" "${SYNC_TAG}" 2>/dev/null || true
  ;;

*)
  error "Error: Invalid command." >&2
  printf "Usage: %s {build|clean}\n" "$0"
  exit 1
  ;;
esac
