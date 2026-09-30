#!/bin/bash
# apps/fortress/agents/aider.sh — aider seat spec.
#
# Sourced by fortress-exec. Contributes only image, mounts, env, and command;
# the security baseline is applied by the caller.
#
# aider runs standalone (no pod) and its model is pinned to
# openrouter/anthropic/claude-3.5-sonnet, so it needs only OPENROUTER_API_KEY.
# That key is fetched here rather than inherited, keeping it out of the zellij
# session and the host nvim pane.
#
# Invoked as: fortress-exec aider [args...]

if [ -n "${ROLE:-}" ]; then
  error "aider takes no role: fortress-exec aider"
  exit 1
fi

F_IMAGE="docker.io/paulgauthier/aider-full:latest"
F_JAIL_HOME="/home/appuser"
F_JAIL_WORK="$F_JAIL_HOME/workspace/$REL_PATH"

P_KEY=$(gopass show ai/openrouter-api-key) || {
  error "Could not read the OpenRouter key from the secret store."
  exit 1
}

F_EXTRA_FLAGS=(
  -i
  --tty
  --userns "keep-id"
  -v "$FORTRESS_CACHE/aider:$F_JAIL_HOME/.cache"
  -v "$SEMBLE_CACHE:$F_JAIL_HOME/.semble"
  -v "$FORTRESS_CONFIG/aider:$F_JAIL_HOME/.config"
  -v "$FORTRESS_SHARE/aider:$F_JAIL_HOME/.local/share"
  -v "$FORTRESS_STATE/aider:$F_JAIL_HOME/.local/state"
  -v "$FORTRESS_HOME/.config/git:$F_JAIL_HOME/.config/git:O"
  -v "$TARGET_PATH:$F_JAIL_WORK"
  -w "$F_JAIL_WORK"
  -e "OPENROUTER_API_KEY=$P_KEY"
  -e "AIDER_CHECK_UPDATE=false"
  -e "AIDER_CHAT_HISTORY_FILE=$F_JAIL_HOME/.local/state/chats/$PROJECT_ID-chat.md"
  -e "AIDER_INPUT_HISTORY_FILE=$F_JAIL_HOME/.local/share/$PROJECT_ID.history"
  -e "GIT_CONFIG_GLOBAL=$F_JAIL_HOME/.config/git/config"
)

F_CMD=(
  --no-gitignore
  --watch-files
  --no-analytics
  --no-check-update
  --config "$F_JAIL_HOME/.config/aider.conf.yml"
  --model "openrouter/anthropic/claude-3.5-sonnet"
  "$@"
)
