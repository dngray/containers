#!/bin/sh
set -e

# Pull colors from the central repository library folder
# shellcheck source=lib/colors.sh
. "${CONTAINER_REPO_PATH}/lib/colors.sh"

UI_TAG="${REG_URL:-localhost}/library/aerc/aerc-ui:latest"
SYNC_TAG="${REG_URL:-localhost}/library/aerc/mail-sync:latest"
BRIDGE_TAG="${REG_URL:-localhost}/library/aerc/aerc-bridge:latest"
BRIDGE_VERSION="v3.26.0"

resolve_version() {
  if [ -n "${AERC_VERSION:-}" ]; then
    LATEST_VERSION="${AERC_VERSION}"
  else
    info "==> Querying upstream repository for latest stable release tag..."

    LATEST_VERSION=$(curl -s "https://git.sr.ht/~rjarry/aerc/refs" |
      grep -Eoi 'href="/~rjarry/aerc/archive/[0-9.]+\.tar\.gz"' |
      grep -oP 'archive/\K[0-9.]*[0-9]' | head -n 1 || true)

    if [ -z "$LATEST_VERSION" ]; then
      warn "Could not fetch dynamic tags. Falling back to core engine default..."
      LATEST_VERSION="0.22.0"
    else
      ok "Found current production release layer version: ${LATEST_VERSION}"
    fi
  fi
}

build_images() {
  resolve_version

  info "==> 1/3 Building Interactive UI Client (${UI_TAG})..."
  podman build -f "${CONTAINER_REPO_PATH}/build/aerc-ui/Containerfile" \
    --build-arg LANG=en_US.UTF-8 \
    --build-arg HOST_UID="${HOST_UID}" \
    --build-arg HOST_GID="${HOST_GID}" \
    --build-arg version="${LATEST_VERSION}" \
    -t "${UI_TAG}" "${CONTAINER_REPO_PATH}"

  info "==> 2/3 Building Headless Sync Automation Daemon (${SYNC_TAG})..."
  podman build -f "${CONTAINER_REPO_PATH}/build/mail-sync/Containerfile" \
    --build-arg HOST_UID="${HOST_UID}" \
    --build-arg HOST_GID="${HOST_GID}" \
    -t "${SYNC_TAG}" "${CONTAINER_REPO_PATH}"

  info "==> 3/3 Building Proton Mail Bridge Gateway (${BRIDGE_TAG})..."
  podman build -f "${CONTAINER_REPO_PATH}/build/aerc-bridge/Containerfile" \
    --build-arg ENV_PROTONMAIL_BRIDGE_VERSION="${BRIDGE_VERSION}" \
    -t "${BRIDGE_TAG}" "${CONTAINER_REPO_PATH}/build/aerc-bridge"
}

case "$1" in
build)
  build_images
  ;;

publish)
  build_images

  if [ "${LATEST_VERSION}" = "master" ]; then
    _hash="latest"
  else
    _hash="${LATEST_VERSION}"
  fi

  warn "==> Distributing Aerc [${_hash}] container imagery..."

  podman tag "${UI_TAG}" "${REG_URL}/library/aerc/aerc-ui:${_hash}"
  podman tag "${SYNC_TAG}" "${REG_URL}/library/aerc/mail-sync:${_hash}"
  podman tag "${BRIDGE_TAG}" "${REG_URL}/library/aerc/aerc-bridge:${BRIDGE_VERSION}"

  podman push "${UI_TAG}"
  podman push "${SYNC_TAG}"
  podman push "${BRIDGE_TAG}"
  podman push "${REG_URL}/library/aerc/aerc-ui:${_hash}"
  podman push "${REG_URL}/library/aerc/mail-sync:${_hash}"
  podman push "${REG_URL}/library/aerc/aerc-bridge:${BRIDGE_VERSION}"
  ok "✔ Aerc distribution loop completed!"
  ;;

clean)
  warn "🧹 Purging old Aerc container components and split image assets..."
  podman rm -f aerc-ui aerc-sync aerc-bridge 2>/dev/null || true
  podman image rm "${UI_TAG}" "${SYNC_TAG}" "${BRIDGE_TAG}" 2>/dev/null || true
  ;;

*)
  error "Error: Invalid command." >&2
  printf "Usage: %s {build|publish|clean}\n" "$0"
  exit 1
  ;;
esac
