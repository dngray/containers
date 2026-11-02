#!/bin/sh
set -e

# shellcheck source=lib/cli.sh
REPO_ROOT=$(CDPATH= cd "$(dirname "$0")/../.." && pwd)
. "${REPO_ROOT}/lib/cli.sh"

IMAGE="ghcr.io/sillytavern/sillytavern:latest"
SERVICE="sillytavern.service"
UNIT_SRC="${REPO_ROOT}/systemd/sillytavern/sillytavern.container"
UNIT_DIR="${HOME}/.config/containers/systemd"
UNIT_DST="${UNIT_DIR}/sillytavern.container"
CONFIG_DIR="${HOME}/.config/sillytavern"
DATA_DIR="${HOME}/.local/share/sillytavern"

install_unit() {
  mkdir -p "${UNIT_DIR}"

  if [ -L "${UNIT_DST}" ]; then
    if [ "$(readlink -f "${UNIT_DST}" 2>/dev/null)" != "$(readlink -f "${UNIT_SRC}" 2>/dev/null)" ]; then
      warn "==> ${UNIT_DST} is a symlink to another unit; leaving it untouched."
    fi
  elif [ -e "${UNIT_DST}" ]; then
    warn "==> ${UNIT_DST} already exists and is not this repo's unit; leaving it untouched."
  else
    ln -s "${UNIT_SRC}" "${UNIT_DST}"
    info "==> Installed quadlet unit: ${UNIT_DST}"
  fi

  systemctl --user daemon-reload
}

case "$1" in
pull)
  info "==> Fetching latest SillyTavern engine layers..."
  podman pull "${IMAGE}"
  ;;

start)
  info "==> Preparing SillyTavern host storage..."
  mkdir -p "${CONFIG_DIR}" \
    "${DATA_DIR}/data" \
    "${DATA_DIR}/plugins" \
    "${DATA_DIR}/extensions"

  install_unit

  if ! podman image exists "${IMAGE}"; then
    info "==> SillyTavern image missing, pulling ${IMAGE}..."
    podman pull "${IMAGE}"
  fi

  info "==> Starting SillyTavern quadlet..."
  systemctl --user start "${SERVICE}"

  printf "Waiting for sillytavern container to start..."
  _tries=0
  until [ "$(podman container inspect -f '{{.State.Running}}' sillytavern 2>/dev/null)" = "true" ]; do
    if [ "${_tries}" -ge 120 ]; then
      error "SillyTavern did not start. Inspect: systemctl --user status ${SERVICE}"
      exit 1
    fi
    printf "."
    _tries=$((_tries + 1))
    sleep 0.5
  done
  printf " Live!\n"

  ok "✔ SillyTavern available at http://127.0.0.1:8000"
  ;;

stop)
  info "==> Stopping SillyTavern quadlet..."
  systemctl --user stop "${SERVICE}"
  ok "==> SillyTavern offline."
  ;;

clean)
  warn "🧹 Purging SillyTavern container and image (host config/data kept)..."
  systemctl --user stop "${SERVICE}" 2>/dev/null || true
  podman rm -f sillytavern 2>/dev/null || true
  podman image rm "${IMAGE}" 2>/dev/null || true
  ok "✔ SillyTavern container assets removed."
  ;;

*)
  error "Error: Invalid command sequence." >&2
  printf "Usage: %s {pull|start|stop|clean}\n" "$0"
  exit 1
  ;;
esac
