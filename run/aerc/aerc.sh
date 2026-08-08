#!/bin/sh
set -e

# Pull colors from the central repository library folder
. "${CONTAINER_REPO_PATH}/lib/colors.sh"

IMAGE_TAG="aerc:latest"

# Clean Text Lists
RW_MOUNTS="
.local/share/mail
.local/share/nvim
.local/share/address-book
.local/share/calendars
.local/state/vdirsyncer
.local/state/isync
.local/share/gopass
.gnupg
Downloads
"

RO_MOUNTS="
.local/bin/container-email-sync
.local/bin/osc52-copy
.local/bin/maildrive-split
.config/aerc
.config/vdirsyncer/config
.config/email-common
.config/nvim
.config/goimapnotify/goimapnotify.yaml
.config/khard
.config/msmtp
.config/notmuch
.config/isyncrc
.config/gopass/config
.config/mutt
"

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

  info "==> Building Aerc terminal client container (${LATEST_VERSION})..."
  podman build -f "${CONTAINER_REPO_PATH}/build/aerc/Containerfile" \
    --build-arg LANG=en_US.UTF-8 \
    --build-arg HOST_UID="${HOST_UID}" \
    --build-arg HOST_GID="${HOST_GID}" \
    --build-arg version="${LATEST_VERSION}" \
    -t "${IMAGE_TAG}" "${CONTAINER_REPO_PATH}"
  ;;

run)
  info "==> Assembling configuration layers for Aerc..."

  # Core baseline parameters
  set -- -it --replace \
    --userns=keep-id \
    -u "${HOST_UID}:${HOST_GID}" \
    --hostname aerc \
    --name aerc \
    --security-opt label=type:container_t \
    -e TZ=""

  # Generate Read-Write bind configurations natively
  for mount in $RW_MOUNTS; do
    set -- "$@" --mount "type=bind,source=${HOME}/${mount},target=/home/aerc/${mount}"
  done

  # Generate Read-Only configurations securely
  for mount in $RO_MOUNTS; do
    set -- "$@" --mount "type=bind,source=${HOME}/${mount},target=/home/aerc/${mount},readonly"
  done

  # Inject user runtime execution sockets
  set -- "$@" --mount "type=bind,source=/run/user/${HOST_UID},target=/run/user/${HOST_UID},readonly"

  warn "Bootstrapping interactive terminal interface..."
  exec podman run "$@" localhost/${IMAGE_TAG}
  ;;

clean)
  warn "🧹 Purging old Aerc containers and image assets..."
  podman rm -f aerc 2>/dev/null || true
  podman image rm "${IMAGE_TAG}" 2>/dev/null || true
  ;;

*)
  error "Error: Invalid command." >&2
  printf "Usage: %s {build|run|clean}\n" "$0"
  exit 1
  ;;
esac
