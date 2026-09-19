#!/bin/sh

# Shared bootstrap for all container-management scripts.
# Terminal colors, environment policy, and local runtime configuration.

# ── Terminal Colors ──
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Strip colors if we aren't printing to a live interactive terminal
if [ ! -t 1 ]; then
  RED=''
  GREEN=''
  YELLOW=''
  CYAN=''
  BOLD=''
  NC=''
fi

info() { printf '%b%b%s%b\n' "$CYAN" "$BOLD" "$*" "$NC"; }
ok() { printf '%b%s%b\n' "$GREEN" "$*" "$NC"; }
warn() { printf '%b%s%b\n' "$YELLOW" "$*" "$NC"; }
error() { printf '%b%s%b\n' "$RED" "$*" "$NC"; }
item() { printf '  %b%-23s%b %s\n' "$GREEN" "$1" "$NC" "$2"; }

# Quietly source environment policy definitions if present
if [ -f "$HOME/.config/containers/containers.env" ]; then
  # shellcheck source=/dev/null
  . "$HOME/.config/containers/containers.env"
fi

# Securely export local runtime configurations
REG_URL="$(printf '%s' "${REG_URL:-}" | tr -d '"')"
export REG_URL
HOST_UID="$(id -u)"
export HOST_UID
HOST_GID="$(id -g)"
export HOST_GID