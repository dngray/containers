#!/bin/bash
# apps/fortress/agents/goose.sh — goose seat spec.
#
# Sourced by fortress-exec. Contributes only image, mounts, env, and command;
# the security baseline is applied by the caller.
#
# goose is not opencode and has no auth.json store, so its provider key is
# fetched here and passed inline as GOOSE_PROVIDER's key. Only the key for the
# active GOOSE_MODE is fetched -- the seat never receives the other provider's
# credential.
#
# Invoked as: fortress-exec goose server|session

case "${ROLE:-}" in
server | session) ;;
*)
  error "goose requires a role: fortress-exec goose server|session"
  exit 1
  ;;
esac

# Both roles share the pod. Skipped under --print-plan so planning works
# before the first launch and without podman on PATH.
if [ "${PRINT_PLAN:-0}" != "1" ]; then
  podman pod exists "$POD_NAME" || {
    error "Pod $POD_NAME not found. Launch via fortress."
    exit 1
  }
fi

F_JAIL_HOME="/home/goose"
F_JAIL_WORK="$F_JAIL_HOME/workspace/$REL_PATH"

G_MODE=${GOOSE_MODE:-nanogpt}
case "$G_MODE" in
openrouter)
  P_HOST="openrouter.ai"
  P_SECRET=ai/openrouter-api-key
  P_MODEL="anthropic/claude-3.5-sonnet"
  ;;
nanogpt)
  P_HOST="nano-gpt.com"
  P_SECRET=ai/openai-api-key
  P_MODEL="gpt-4o"
  ;;
*)
  error "Unknown Goose Mode: $G_MODE"
  exit 1
  ;;
esac

P_KEY=$(gopass show "$P_SECRET") || {
  error "Could not read the goose provider key from the secret store."
  exit 1
}

F_IMAGE="$(fortress_registry goose)/goose/$(
  [ "$ROLE" = session ] && printf 'goose-cli' || printf 'goose-server'
):latest"

F_EXTRA_FLAGS=(
  --pod "$POD_NAME"
  --group-add keep-groups
  -v "$FORTRESS_CACHE/goose:$F_JAIL_HOME/.cache"
  -v "$FORTRESS_CONFIG/goose:$F_JAIL_HOME/.config/goose"
  -v "$SEMBLE_CACHE:$F_JAIL_HOME/.semble"
  -v "$TARGET_PATH:$F_JAIL_WORK"
  -w "$F_JAIL_WORK"
  -e "GOOSE_PROVIDER=openai"
  -e "GOOSE_PATH=/api/v1"
  -e "GOOSE_HOST=$P_HOST"
  -e "GOOSE_PORT=443"
  -e "GOOSE_MODEL=$P_MODEL"
  -e "OPENAI_API_KEY=$P_KEY"
  -e "GOOSE_TELEMETRY_ENABLED=false"
)

if [ "$ROLE" = "session" ]; then
  F_EXTRA_FLAGS+=("-i" "--tty" "--entrypoint" "bash")

  # Wait for the in-pod goose-server listener (5005) before starting the
  # session. In-pod netns share; a host-side probe cannot see it. 60s budget,
  # then proceed anyway (fortress-probe parity).
  F_CMD=(-ec '
    deadline=$((SECONDS + 60))
    until curl -s -o /dev/null --max-time 2 http://127.0.0.1:5005; do
      [ "$SECONDS" -ge "$deadline" ] && break
      sleep 0.5
    done
    exec goose session
  ')
else
  F_EXTRA_FLAGS+=("-i")
  F_CMD=(serve --port 5005 --host 0.0.0.0)
fi
