#!/bin/sh

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
item() { printf '  %b%s%b\t %s\n' "$GREEN" "$1" "$NC" "$2"; }
