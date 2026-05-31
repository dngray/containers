#!/bin/sh
set -e

# Pull colors from the central repository library folder
# shellcheck source=lib/colors.sh
. "${CONTAINER_REPO_PATH}/lib/colors.sh"

CMD="${CMD:-docker}"
ENV_FILE="compose/.env"

# Deploy stages: wireguard tunnels (serial), independent services (parallel), edge proxy (serial)
SERVICES_STAGE1="stepca wg1_qbt wg2_usenet wg3_general"
SERVICES_STAGE2="beets caddy cinny flexo harbor mumble music powerwall rss smb syncthing vault vaultwarden"
SERVICES_STAGE3="traefik"

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
  _extra_files=""
  _extra_env=""

  case "$_service" in
  syncthing) _extra_files="-f ${CONTAINER_REPO_PATH}/compose/syncthing/volumes.yml" ;;
  powerwall) _extra_env="--env-file ${CONTAINER_REPO_PATH}/compose/powerwall/data/compose.env" ;;
  esac

  info "==> Deploying infrastructure layer: ${_service}..."
  set -- run_privileged "${CMD}" compose --env-file "${CONTAINER_REPO_PATH}/${ENV_FILE}" \
    $_extra_env -f "${CONTAINER_REPO_PATH}/compose/${_service}/compose.yml" $_extra_files "${_action}"
  [ -n "$_extra_action_flags" ] && set -- "$@" "$_extra_action_flags"
  "$@" -d
}

# Create shared traefik proxy network once (idempotent)
_init_traefik_network() {
  if ! run_privileged "${CMD}" network ls -q -f name=^traefik$ 2>/dev/null | grep -q .; then
    info "==> Creating shared edge proxy network: traefik..."
    run_privileged "${CMD}" network create \
      --driver bridge \
      --subnet 172.20.0.0/24 \
      --ip-range 172.20.0.0/24 \
      --label "com.docker.compose.network=traefik" \
      traefik
  fi
}

# Deploy all stages: stage 1 serial, stage 2 parallel, stage 3 serial
_deploy_all() {
  _action="$1"
  _extra_action_flags="${2:-}"

  _init_traefik_network

  for service in $SERVICES_STAGE1; do
    run_compose "${service}" "${_action}" "${_extra_action_flags}"
  done

  for service in $SERVICES_STAGE2; do
    run_compose "${service}" "${_action}" "${_extra_action_flags}" &
  done
  wait

  for service in $SERVICES_STAGE3; do
    run_compose "${service}" "${_action}" "${_extra_action_flags}"
  done
}

case "$1" in
up-build)
  info "==> Rebuilding and bringing up all compose services..."
  _deploy_all "up" "--build"
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
  _deploy_all "up" ""
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
