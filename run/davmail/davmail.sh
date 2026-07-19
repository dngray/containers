#!/bin/sh
set -e

# Pull colors from the central repository library folder
. "${CONTAINER_REPO_PATH}/lib/colors.sh"

case "$1" in
build)
  info "==> Assembling custom DavMail translator gateway..."
  # Explicitly points to your unified repository folder tree paths
  podman build -f "${CONTAINER_REPO_PATH}/run/davmail/Dockerfile" \
    -t davmail:latest "${CONTAINER_REPO_PATH}/run/davmail"
  ;;

run)
  info "==> Launching DavMail active exchange bridge..."
  podman run -it --replace --userns=keep-id \
    -p 1143:1143 -p 1025:1025 \
    -v "${HOME}/.config/davmail/davmail_manual.properties:/davmail/davmail.properties:ro,z" \
    -v "${HOME}/.local/lib/davmail/tokens.properties:/davmail/tokens.properties:z" \
    -v "${HOME}/.local/log/davmail/davmail.log:/davmail/davmail.log:z" \
    --name davmail \
    localhost/davmail:latest /davmail/davmail.properties
  ;;

clean)
  warn "🧹 Purging DavMail containers and translation caches..."
  podman rm -f davmail 2>/dev/null || true
  podman image rm davmail:latest 2>/dev/null || true
  ;;

*)
  error "Error: Invalid command sequence." >&2
  printf "Usage: %s {build|run|clean}\n" "$0"
  exit 1
  ;;
esac
