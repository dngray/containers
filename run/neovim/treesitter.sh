#!/bin/sh
set -e

# Pull colors from the central repository library folder
# shellcheck source=lib/colors.sh
. "${CONTAINER_REPO_PATH}/lib/colors.sh"

IMAGE_TAG="local-nvim-compiler:latest"

case "$1" in
build)
  info "==> Compiling isolated, immutable local Neovim build environment..."
  podman build -f "${CONTAINER_REPO_PATH}/build/neovim/Containerfile" \
    --build-arg HOST_UID="${HOST_UID}" \
    --build-arg HOST_GID="${HOST_GID}" \
    -t "${IMAGE_TAG}" "${CONTAINER_REPO_PATH}"
  ok "Custom compiler image built successfully."
  ;;

update)
  info "==> Stabilizing host path contexts for Neovim..."
  mkdir -p "${HOME}/.config/nvim"
  mkdir -p "${HOME}/.local/share/nvim/site/parser"

  info "==> Executing synchronous compilation cascade..."

  # 1. We inject -e COMPILE_PARSERS=1 so your LazyVim configuration populates the 25 languages.
  # 2. We use -c "TSInstall! all" to force foreground synchronous compilation inside the container.
  # 3. We append "+messages" to dump the compilation progress text directly to your shell stdout.
  podman run --rm -it \
    --name nvim-parser-builder \
    --security-opt label=disable \
    --userns=keep-id \
    -e COMPILE_PARSERS=1 \
    -v "${HOME}:${HOME}:rw" \
    "${IMAGE_TAG}" \
    nvim --headless -c "TSInstall! all" -c "q" +messages

  ok "Treesitter parsers successfully compiled and linked to host runtime."
  ;;

clean)
  warn "🧹 Removing local nvim compiler image layers..."
  podman image rm "${IMAGE_TAG}" 2>/dev/null || true
  ;;

*)
  error "Error: Invalid command." >&2
  printf "Usage: %s {build|update|clean}\n" "$0"
  exit 1
  ;;
esac
