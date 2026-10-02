#!/bin/bash
# apps/fortress/agents/opencode.sh — opencode seat spec.
#
# Sourced by fortress-exec. Contributes only image, mounts, env, and command;
# the security baseline is applied by the caller.
#
# Provider API keys are NOT injected here. They live in auth.json inside the
# share bind mount, which opencode reads natively. Injecting them as -e vars
# would be redundant with the credential store and would widen their exposure
# to anything that can read the container's process environment.
#
# Invoked as: fortress-exec opencode server|tui

case "${ROLE:-}" in
server | tui) ;;
*)
  error "opencode requires a role: fortress-exec opencode server|tui"
  exit 1
  ;;
esac

# Generation selector. `fortress` exports it and `just` always sets it, but
# fortress-exec is also a documented standalone entrypoint for restarting a
# single in-pane seat -- resolve it here as well, or the seat dies on `set -u`
# before it can pick a port. v2 is the default; v1 stays selectable.
OPENCODE_API="${OPENCODE_API:-v2}"

# Both roles share the pod; the server pane starts first and the TUI waits.
# Skipped under --print-plan: planning is meant to work before the first
# launch, and it must not need podman on PATH just to render an argv.
if [ "${PRINT_PLAN:-0}" != "1" ]; then
  podman pod exists "$POD_NAME" || {
    error "Pod $POD_NAME not found. Launch via fortress."
    exit 1
  }
fi

F_JAIL_HOME="/home/opencode"
F_JAIL_WORK="$F_JAIL_HOME/workspace/$REL_PATH"

F_EXTRA_FLAGS=(
  --pod "$POD_NAME"
  --group-add keep-groups
  -v "$FORTRESS_CACHE/opencode:$F_JAIL_HOME/.cache"
  -v "$FORTRESS_CONFIG/opencode/share:$F_JAIL_HOME/.local/share/opencode"
  -v "$FORTRESS_CONFIG/opencode/state:$F_JAIL_HOME/.local/state/opencode"
  -v "$SEMBLE_CACHE:$F_JAIL_HOME/.semble"
  -v "$TARGET_PATH:$F_JAIL_WORK"
  -w "$F_JAIL_WORK"
  -e "SEMBLE_CACHE_LOCATION=$F_JAIL_HOME/.semble"
)

# Per-project DB credentials as dotenv (see apps/fortress/readme.md). Mounted
# only when present -- bind sources must exist at launch or podman aborts.
PGPASS_ENV="$FORTRESS_CONFIG/opencode/$PROJECT_ID/pgpass.env"
if [ -f "$PGPASS_ENV" ]; then
  F_EXTRA_FLAGS+=(-v "$PGPASS_ENV:$F_JAIL_HOME/.pgpass.env")
fi

# ---------------------------------------------------------------------------
# The server bind-password has no config or auth-store representation in
# opencode, so it is passed as a container env var. It is fetched here, per
# pane, rather than inherited from the launcher, which keeps it out of the
# zellij session and out of the host nvim pane.
# ---------------------------------------------------------------------------
F_SERVER_PASSWORD=$(gopass show ai/opencode-server-pass) || {
  error "Could not read the server password from the secret store."
  exit 1
}
F_SERVER_USERNAME=${FORTRESS_SERVER_USERNAME:-opencode}

PORT=$(fortress_api_port "$OPENCODE_API") || {
  error "Unknown opencode API generation '$OPENCODE_API' (expected v1 or v2)."
  exit 1
}
PROBE_PATH=$(fortress_api_probe_path "$OPENCODE_API")
SERVER_URL="http://127.0.0.1:$PORT"
F_VARIANT=${OPENCODE_VARIANT:-latest}
F_IMAGE=$(fortress_opencode_image "$ROLE") || {
  error "Invalid opencode image role/variant '$ROLE'/'${OPENCODE_VARIANT:-latest}'."
  exit 1
}

if [ "$ROLE" = "server" ]; then
  F_EXTRA_FLAGS+=("-i")
  F_EXTRA_FLAGS+=(-e "OPENCODE_SERVER_USERNAME=$F_SERVER_USERNAME")
  F_EXTRA_FLAGS+=(-e "OPENCODE_SERVER_PASSWORD=$F_SERVER_PASSWORD")
  F_CMD=(serve --port "$PORT" --hostname 127.0.0.1)
else
  F_EXTRA_FLAGS+=(-e "OPENCODE_SERVER_USERNAME=$F_SERVER_USERNAME")
  F_EXTRA_FLAGS+=(-e "OPENCODE_SERVER_PASSWORD=$F_SERVER_PASSWORD")
  F_EXTRA_FLAGS+=("-i" "--tty" "--entrypoint" "bash")

  # Wait for the in-pod server listener before attaching. This loop runs inside
  # the pod network namespace, which shares 127.0.0.1 with the server; a
  # host-side probe cannot see a loopback-only listener. 60s budget, then
  # proceed anyway so the attach surfaces its own error (fortress-probe parity).
  #
  # v2 deleted the `attach` subcommand: the TUI is now the ROOT command and
  # takes --server plus an optional [directory] positional (confirmed against
  # `opencode --help` for 2.0.22). v1 keeps `attach ... --dir`. The password is
  # read from the environment in both, since neither generation has a flag for
  # it on the TUI side.
  case "${OPENCODE_API}" in
    v1) F_ATTACH="exec opencode attach \"${SERVER_URL}\" --password \"\${OPENCODE_SERVER_PASSWORD}\" --dir ." ;;
    v2) F_ATTACH="exec opencode --server \"${SERVER_URL}\" ." ;;
  esac
  F_CMD=(-ec "
    deadline=\$((SECONDS + 60))
    until curl -fs -u \"${F_SERVER_USERNAME}:\${OPENCODE_SERVER_PASSWORD}\" -o /dev/null --max-time 2 \"${SERVER_URL}${PROBE_PATH}\"; do
      [ \"\$SECONDS\" -ge \"\$deadline\" ] && break
      sleep 0.5
    done
    ${F_ATTACH}
  ")
fi
