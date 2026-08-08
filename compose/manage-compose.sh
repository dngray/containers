#!/bin/sh
set -e

# Pull colors from the central repository library folder
# shellcheck source=lib/colors.sh
. "${CONTAINER_REPO_PATH}/lib/colors.sh"

CMD="${CMD:-docker}"
ENV_FILE="compose/.env"

# Definitive single-source order for cluster deployment
SERVICES="stepca harbor mumble wg1_qbt wg2_usenet wg3_general beets rss vaultwarden vault syncthing smb flexo cinny powerwall grafana caddy music traefik"

# Privileged Handler Function: Prioritizes sudo over run0
run_privileged() {
  if command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  elif command -v run0 >/dev/null 2>&1; then
    run0 "$@"
  else
    "$@"
  fi
}

# Clean helper function to deploy a service layer
run_compose() {
  _service="$1"
  _action="$2"
  _extra_action_flags="$3"

  info "==> Deploying infrastructure layer: ${_service}..."
  set -- run_privileged "${CMD}" compose --env-file "${CONTAINER_REPO_PATH}/${ENV_FILE}" \
    -f "${CONTAINER_REPO_PATH}/compose/${_service}/compose.yml" "${_action}"
  [ -n "$_extra_action_flags" ] && set -- "$@" "$_extra_action_flags"
  "$@" -d
}

case "$1" in
up-build)
  info "==> Rebuilding and bringing up all compose services..."
  for service in $SERVICES; do
    run_compose "${service}" "up" "--build"
  done
  ok "✔ All compose service layers successfully rebuilt and established!"
  ;;

traefik-build)
  info "==> Building edge proxy assets: traefik..."
  run_compose "traefik" "up" "--build"
  ;;

music-build)
  info "==> Building music stack: mpd, snapcast, cyp..."
  run_compose "music" "up" "--build"
  ;;

all-up)
  warn "Bootstrapping application matrix containers..."
  for service in $SERVICES; do
    run_compose "${service}" "up" ""
  done
  ok "✔ All cluster service layers successfully established!"
  ;;

stop-all)
  warn "==> Stopping all active container nodes on the VM..."
  _ids=$(run_privileged "${CMD}" ps -aq)
  if [ -n "$_ids" ]; then
    # shellcheck disable=SC2086
    set -- $_ids
    run_privileged "${CMD}" stop "$@"
  else
    ok "No running containers found."
  fi
  ;;

rm-all)
  error "==> Vaporizing all container states from storage..."
  _ids=$(run_privileged "${CMD}" ps -aq)
  if [ -n "$_ids" ]; then
    # shellcheck disable=SC2086
    set -- $_ids
    run_privileged "${CMD}" rm "$@"
  else
    ok "No containers to remove."
  fi
  ;;

rmi-all)
  error "==> Flushing all local Docker image layers..."
  _imgs=$(run_privileged "${CMD}" images -q)
  if [ -n "$_imgs" ]; then
    # shellcheck disable=SC2086
    set -- $_imgs
    run_privileged "${CMD}" rmi "$@"
  else
    ok "No images to clear."
  fi
  ;;

prune-net)
  warn "==> Removing stopped containers and pruning unused virtual network bridges..."
  run_privileged "${CMD}" container prune -f
  run_privileged "${CMD}" network prune -f
  ;;

*)
  error "Error: Invalid command target sequence." >&2
  exit 1
  ;;
esac
