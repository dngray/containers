#!/bin/sh
set -e

. "${CONTAINER_REPO_PATH}/lib/colors.sh"

TFTP_IMG="localhost/tftpd-hpa:local"

TFTP_DIR="/tmp/tftpboot"

case "$1" in
build)
  info "==> Building Hardened TFTP server container..."
  podman build -f "${CONTAINER_REPO_PATH}/build/tftp/Containerfile" \
    -t "${TFTP_IMG}" "${CONTAINER_REPO_PATH}/build/tftp"
  ;;

run)
  mkdir -p "${TFTP_DIR}"
  info "==> Ensuring image is available in rootful storage..."
  if ! run0 podman image exists "${TFTP_IMG}" 2>/dev/null; then
    run0 podman build -f "${CONTAINER_REPO_PATH}/build/tftp/Containerfile" \
      -t "${TFTP_IMG}" "${CONTAINER_REPO_PATH}/build/tftp"
  fi
  info "==> Launching TFTP daemon server (rootful)..."
  run0 podman run -d --replace --network host \
    -v "${TFTP_DIR}:/var/tftpboot:z" \
    --security-opt label=disable \
    --name tftp \
    "${TFTP_IMG}"
  info "==> TFTP serving ${TFTP_DIR} on port 69/udp"
  ;;

clean)
  warn "==> Removing TFTP container assets and image..."
  run0 podman rm -f tftp 2>/dev/null || true
  podman rm -f tftp 2>/dev/null || true
  run0 podman image rm "${TFTP_IMG}" 2>/dev/null || true
  podman image rm "${TFTP_IMG}" 2>/dev/null || true
  ;;

*)
  error "Error: Unknown tftp action. Use build, run, or clean."
  exit 1
  ;;
esac
