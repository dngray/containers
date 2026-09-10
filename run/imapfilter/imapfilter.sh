#!/bin/sh
set -e

# Pull colors from the central repository library folder
. "${CONTAINER_REPO_PATH}/lib/colors.sh"

IMAGE_TAG="imapfilter:latest"

case "$1" in
build)
  # Replaces Makefile's $(shell date) with native runtime execution
  _date=$(date '+%Y-%m-%d-%H:%M:%S')

  info "==> Building Imapfilter container [${_date}]..."
  # Explicitly scopes file lookups directly to your unified repository tree path
  podman build -f "${CONTAINER_REPO_PATH}/build/imapfilter/Containerfile" \
    --build-arg BUILD_DATE="${_date}" \
    -t "${IMAGE_TAG}" "${CONTAINER_REPO_PATH}"
  ;;

run)
  info "==> Executing secure Imapfilter runtime pass..."

  # Non-interactive background run mapping your exact capabilities and environment
  exec podman run --replace --userns=keep-id \
    -v "${HOME}/.config/imapfilter:/home/imapfilter/.config/imapfilter:z,ro" \
    -v "${HOME}/.vault-token:/home/imapfilter/.vault-token:z,ro" \
    --name imapfilter \
    --cap-add=IPC_LOCK \
    -e VAULT_ADDR \
    "localhost/${IMAGE_TAG}"
  ;;

clean)
  warn "🧹 Purging Imapfilter containers and cached layers..."
  podman rm -f imapfilter 2>/dev/null || true
  podman image rm "${IMAGE_TAG}" 2>/dev/null || true
  ;;

*)
  error "Error: Invalid command target sequence." >&2
  printf "Usage: %s {build|run|clean}\n" "$0"
  exit 1
  ;;
esac
