#!/bin/sh
set -e

# shellcheck source=lib/cli.sh
REPO_ROOT=$(CDPATH= cd "$(dirname "$0")/../.." && pwd)
. "${REPO_ROOT}/lib/cli.sh"

case "$1" in
pull)
  info "==> Fetching latest Crowdin CLI engine layers..."
  podman pull docker.io/crowdin/cli:latest
  ;;

run)
  info "==> Initializing interactive Crowdin workspace session..."
  podman run -it --replace --userns=keep-id \
    -v "${HOME}/src:/src:z" \
    --env-file "${REPO_ROOT}/apps/crowdin/.env" \
    --name crowdin \
    docker.io/crowdin/cli:latest
  ;;

clean)
  warn "🧹 Dismantling Crowdin workspace containers..."
  podman rm -f crowdin 2>/dev/null || true
  podman image rm docker.io/crowdin/cli:latest 2>/dev/null || true
  ;;

*)
  error "Error: Invalid command sequence." >&2
  printf "Usage: %s {pull|run|clean}\n" "$0"
  exit 1
  ;;
esac
