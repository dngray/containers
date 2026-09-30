#!/bin/sh
# lib/fortress.sh — single source of truth for Fortress seat definitions.
#
# Sourced by apps/fortress/fortress (host launcher) and
# apps/fortress/fortress-exec (in-pane executor) plus each
# apps/fortress/agents/<tool>.sh. Every mode-specific value lives here so the
# launchers never disagree about ports, paths, images, or probe endpoints.
#
# POSIX sh. No side effects beyond variable definitions.

# ---------------------------------------------------------------------------
# Home directory.
#
# Resolved from the passwd database, not $HOME. The policy's HOME_DIR macro
# also comes from passwd, so deriving our roots the same way keeps the shell
# checks and the SELinux labels agreeing by construction. Under systemd-homed
# that is /var/home/<user>, and a long-lived shell (or one inherited from
# before the homed migration) can still carry a stale HOME=/home/<user> --
# which made a perfectly valid path fail the source-root check below.
# ---------------------------------------------------------------------------
if [ -z "${FORTRESS_HOME:-}" ]; then
  FORTRESS_HOME=$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f6)
  [ -n "$FORTRESS_HOME" ] || FORTRESS_HOME="${HOME:-/root}"
fi

# ---------------------------------------------------------------------------
# Layout paths. The state root was renamed (see
# apps/fortress/selinux/*/*.fc for the matching label rules).
# ---------------------------------------------------------------------------
FORTRESS_CONFIG="${FORTRESS_CONFIG:-$FORTRESS_HOME/.config/fortress}"
FORTRESS_CACHE="${FORTRESS_CACHE:-$FORTRESS_HOME/.cache/fortress}"
FORTRESS_SHARE="${FORTRESS_SHARE:-$FORTRESS_HOME/.local/share/fortress}"
FORTRESS_STATE="${FORTRESS_STATE:-$FORTRESS_HOME/.local/state/fortress}"

# Semble index cache is shared by every agent seat.
SEMBLE_CACHE="$FORTRESS_CACHE/semble"

# ---------------------------------------------------------------------------
# Host state directories that must exist before a seat launches. Podman aborts
# on a missing bind-mount source, so these are created up front.
# ---------------------------------------------------------------------------
FORTRESS_POD_PREFIX="fortress-pod"

# podman pod name for a project (the seat shares one pod across panes).
fortress_pod_name() {
  printf '%s-%s' "$FORTRESS_POD_PREFIX" "$1"
}

# ---------------------------------------------------------------------------
# Supported agents and API generations.
# ---------------------------------------------------------------------------
FORTRESS_AGENTS="aider goose opencode"
FORTRESS_APIS="v1 v2"
FORTRESS_VARIANTS="latest full-binary basic-binary"

# Per-agent key set. Providers authenticate from ~/.local/share/opencode/auth.json
# (masked into the container by the share bind mount), so these are NOT injected
# as container env vars. The set is retained for the gopass pre-flight and for
# goose, which needs its key inline because goose is not opencode.
#
#   opencode -> provider keys, delivered via auth.json
#   goose    -> exactly one key by GOOSE_MODE, passed as GOOSE_PROVIDER's key
#   aider    -> OPENROUTER_API_KEY (its model is openrouter/anthropic/...)
fortress_agent_keys() {
  case "$1" in
  opencode) printf '%s\n' ai/openrouter-api-key ai/openai-api-key ai/anthropic-api-key ;;
  goose)
    case "${GOOSE_MODE:-nanogpt}" in
    openrouter) printf '%s\n' ai/openrouter-api-key ;;
    *) printf '%s\n' ai/openai-api-key ;;
    esac
    ;;
  aider) printf '%s\n' ai/openrouter-api-key ;;
  *) return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# opencode API generation differences.
#
# The two generations differ only in the HTTP port, the readiness probe path,
# and the server/client argv. Everything else (image, mounts, labels) is
# identical, which is what makes the v1/v2 diff gate meaningful.
# ---------------------------------------------------------------------------
fortress_api_port() {
  case "$1" in
  v1) printf '4096' ;;
  v2) printf '49374' ;;
  *) return 1 ;;
  esac
}

# Readiness probe path. v1 serves the TUI at /; v2 serves a JSON API info
# document at /api/info.
fortress_api_probe_path() {
  case "$1" in
  v1) printf '/' ;;
  v2) printf '/api/info' ;;
  *) return 1 ;;
  esac
}

# Resolve the container registry namespace. lib/cli.sh sources
# ~/.config/containers/containers.env and exports REG_URL.
fortress_registry() {
  printf '%s' "${REG_URL:-localhost}/library/$1"
}

# Resolve an opencode image reference for a role (server|tui).
# Tags are variant-only: the API generation selects which *config* is baked,
# not which image is pulled, so F_API deliberately does not appear here.
fortress_opencode_image() {
  case "$1" in
  server | tui) ;;
  *) return 1 ;;
  esac
  case "${F_VARIANT:-latest}" in
  latest | full-binary | basic-binary) ;;
  *) return 1 ;;
  esac
  printf '%s/opencode-%s:%s' "$(fortress_registry opencode)" "$1" "$F_VARIANT"
}

# ---------------------------------------------------------------------------
# Workspace path mapping.
#
# A target path must live under a root the SELinux policy labels as
# fortress_src_t, otherwise the seat cannot read its own workspace. Two roots
# are labelled (see selinux/*/*.fc): ~/src and ~/workspace. Returns the path
# relative to the matching root; fails if the path is outside both, or if it
# matches a root prefix without the trailing separator (so ~/srcfoo does not
# silently map into ~/src).
# ---------------------------------------------------------------------------
# The two labelled roots, resolved to physical paths. Returns 1 if neither
# exists yet (a fresh host), in which case the literal paths are used.
fortress_labelled_roots() {
  for _root in "$FORTRESS_HOME/src" "$FORTRESS_HOME/workspace"; do
    _phys=$(CDPATH= cd -- "$_root" 2>/dev/null && pwd -P) || _phys=$_root
    printf '%s\n' "$_phys"
  done
}

# Map an absolute workspace path to its path relative to a labelled root.
#
# Compared physically, not textually. SELinux stores labels on inodes and
# restorecon follows symlinked home paths, so a tree reached as
# /home/<user>/src/... is frequently the same inode as /var/home/<user>/src/...
# (systemd-homed and the /home compatibility symlink). A textual prefix match
# rejects the very path the policy actually labels.
fortress_rel_path() {
  _abs=$1
  _phys=$(CDPATH= cd -- "$_abs" 2>/dev/null && pwd -P) || _phys=$_abs
  _rel=""
  while IFS= read -r _root; do
    case "$_phys" in
    "$_root"/*)
      _rel=${_phys#"$_root"/}
      break
      ;;
    esac
  done <<EOF
$(fortress_labelled_roots)
EOF
  [ -n "$_rel" ] || return 1
  printf '%s' "$_rel"
}

# Create the per-agent host state directories. Bind-mount sources must exist
# before podman run, otherwise it aborts with a statfs error.
fortress_prepare_dirs() {
  case "$1" in
  aider)
    mkdir -p "$FORTRESS_CONFIG/aider" \
      "$FORTRESS_SHARE/aider" \
      "$FORTRESS_STATE/aider/chats"
    ;;
  opencode)
    mkdir -p "$FORTRESS_CONFIG/opencode/share" \
      "$FORTRESS_CONFIG/opencode/state"
    ;;
  goose)
    mkdir -p "$FORTRESS_CONFIG/goose"
    ;;
  *) return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# Credential delivery.
#
# Provider API keys are written to opencode's own credential store rather than
# passed through the environment:
#
#   ~/.config/fortress/opencode/share/auth.json  (host, 0600)
#     -> bind-mounted to /home/opencode/.local/share/opencode
#     -> read natively by opencode (Global.Path.data/auth.json)
#
# auth.json is never baked into an image (buildah-build.sh copies only
# opencode.jsonc), so credentials stay out of published layers.
#
# The server bind-password has no config or auth-store representation in
# opencode, so it remains an environment variable scoped to the seat pane.
# ---------------------------------------------------------------------------
FORTRESS_AUTH_JSON="$FORTRESS_CONFIG/opencode/share/auth.json"

# Write auth.json from the current environment's *_API_KEY values.
# Creates the store with 0600 before writing so the key never exists in a
# world-readable file, even briefly.
fortress_write_auth_json() {
  mkdir -p "$(dirname "$FORTRESS_AUTH_JSON")"
  (umask 077 && : >"$FORTRESS_AUTH_JSON")

  _openrouter=${OPENROUTER_API_KEY:-}
  _openai=${OPENAI_API_KEY:-}
  _anthropic=${ANTHROPIC_API_KEY:-}

  printf '{' >>"$FORTRESS_AUTH_JSON"
  _first=1
  for _pair in "openrouter:$_openrouter" "openai:$_openai" "anthropic:$_anthropic"; do
    _provider=${_pair%%:*}
    _key=${_pair#*:}
    [ -n "$_key" ] || continue
    [ "$_first" -eq 1 ] || printf ',' >>"$FORTRESS_AUTH_JSON"
    _first=0
    printf '"%s":{"type":"api","key":%s}' "$_provider" \
      "$(printf '%s' "$_key" | jq -Rs .)" >>"$FORTRESS_AUTH_JSON"
  done
  printf '}\n' >>"$FORTRESS_AUTH_JSON"

  chmod 600 "$FORTRESS_AUTH_JSON"
}
