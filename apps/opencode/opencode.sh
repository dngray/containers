#!/bin/bash
# apps/opencode/opencode.sh
#
# Dispatcher for the opencode container pipeline. The single entrypoint the
# justfile recipes call; it resolves the release version/hash, normalises a
# publish variant into the (STACK, SRC, TAIL) dimensions and hands off to
# buildah-build.sh for the actual build/compose work, then distributes the
# composed images.
#
# The variant name -> dimension mapping:
#   "" | full        -> STACK=full  SRC=source  TAIL=""         (:latest)
#   binary|full-binary -> STACK=full  SRC=binary  TAIL=full-binary
#   basic            -> STACK=basic SRC=source  TAIL=basic
#   basic-binary     -> STACK=basic SRC=binary  TAIL=basic-binary
#
# Distribution rules:
#   default variant (TAIL="")   -> push :latest, :<version>, :<hash>
#   anything else (TAIL != "")  -> push :<tail>, :<tail>-<hash>
# Binary variants pin OPENCODE_TAG to a release (spinning it up is a sanity
# guard against a moved/renamed tag), source variants build the tag resolved
# from LATEST_VERSION.

set -euo pipefail

# shellcheck disable=SC1007  # repo-convention empty assignment in CDPATH= cd
REPO_ROOT=$(CDPATH= cd "$(dirname "$0")/../.." && pwd)
. "${REPO_ROOT}/lib/cli.sh"

SERVER_IMG="${REG_URL}/library/opencode/opencode-server"
TUI_IMG="${REG_URL}/library/opencode/opencode-tui"

BUILDAH="${REPO_ROOT}/apps/opencode/buildah-build.sh"


# ---------------------------------------------------------------------------
# resolve_version()
#
# Description: resolves and exports LATEST_VERSION (upstream stable release)
#   and RESOLVED_HASH (short commit hash of OPENCODE_TAG / that version).
#   LATEST_VERSION falls back to 1.17.0 if the GitHub API is unreachable;
#   RESOLVED_HASH tries the peeled tag, the plain tag, then HEAD.
# Globals:
#   LATEST_VERSION (string): set if empty; exported for buildah-build.sh
#   RESOLVED_HASH (string): set if empty; exported for buildah-build.sh
#   OPENCODE_TAG (string): optional; read only for hash resolution
# Outputs:
#   Exports LATEST_VERSION and RESOLVED_HASH
# ---------------------------------------------------------------------------
resolve_version() {
  if [ -z "${LATEST_VERSION:-}" ]; then
    info "==> Querying upstream repository for latest stable release tag..."
    LATEST_VERSION=$(curl -s "https://api.github.com/repos/anomalyco/opencode/releases/latest" |
      jq -r .tag_name | sed 's/^v//' || true)

    if [ -z "$LATEST_VERSION" ]; then
      warn " Could not fetch dynamic tags. Falling back to core engine default baseline..."
      LATEST_VERSION="1.17.0"
    else
      ok " Found current production release version: ${LATEST_VERSION}"
    fi
  fi

  if [ -z "${RESOLVED_HASH:-}" ]; then
    resolved_tag="${OPENCODE_TAG:-v${LATEST_VERSION}}"
    RESOLVED_HASH=$(git ls-remote "https://github.com/anomalyco/opencode.git" "refs/tags/${resolved_tag}^{}" 2>/dev/null | cut -c1-7 || true)
    if [ -z "${RESOLVED_HASH}" ]; then
      RESOLVED_HASH=$(git ls-remote "https://github.com/anomalyco/opencode.git" "refs/tags/${resolved_tag}" 2>/dev/null | cut -c1-7 || true)
    fi
    if [ -z "${RESOLVED_HASH}" ]; then
      RESOLVED_HASH=$(git ls-remote "https://github.com/anomalyco/opencode.git" HEAD 2>/dev/null | cut -c1-7 || true)
    fi
    if [ -n "${RESOLVED_HASH}" ]; then
      ok " Locked hash for tag ${resolved_tag}: ${RESOLVED_HASH}"
    else
      warn " Could not resolve tag hash for ${resolved_tag}; leaving to compiler–runtime baseline..."
    fi
  fi
  export LATEST_VERSION RESOLVED_HASH
}


# ---------------------------------------------------------------------------
# set_variant(<variant_name>)
#
# Description: normalises a publish variant name into the exported
#   STACK/SRC/TAIL dimensions and a default OPENCODE_TAG for binary builds.
# Args:
#   $1  variant_name (string): "" | full | binary | full-binary | basic |
#       basic-binary
# Globals:
#   OPENCODE_TAG (string): set to v1.18.31 for binary variants when unset
# Outputs:
#   Exports STACK, SRC, TAIL and OPENCODE_TAG
# Returns:
#   Exits 1 on unknown variant names
# ---------------------------------------------------------------------------
set_variant() {
  case "${1:-}" in
    "" | full)
      STACK="full"
      SRC="source"
      TAIL=""
      ;;
    binary | full-binary)
      STACK="full"
      SRC="binary"
      TAIL="full-binary"
      OPENCODE_TAG="${OPENCODE_TAG:-v1.18.31}"
      ;;
    basic)
      STACK="basic"
      SRC="source"
      TAIL="basic"
      ;;
    basic-binary)
      STACK="basic"
      SRC="binary"
      TAIL="basic-binary"
      OPENCODE_TAG="${OPENCODE_TAG:-v1.18.31}"
      ;;
    *)
      error "Error: Unknown publish variant '$1' (expected full, full-binary, basic, basic-binary)."
      exit 1
      ;;
  esac
  export STACK SRC TAIL OPENCODE_TAG
  info "==> Variant: stack=${STACK} src=${SRC} tail=${TAIL:-latest}"
}


# ---------------------------------------------------------------------------
# build_layers()
#
# Description: builds (and pushes) every layer image the active variant
#   needs, without composing the finals.
# Globals:
#   VARIANT (string): optional; overrides the default (full/source) variant
# Outputs:
#   Side effects: layer images present locally + pushed to registry
# ---------------------------------------------------------------------------
build_layers() {
  set_variant "${VARIANT:-}"
  resolve_version
  "${BUILDAH}" layers
}


# ---------------------------------------------------------------------------
# build_server()
#
# Description: composes just the opencode-server image for the active variant.
# Globals:
#   VARIANT (string): optional; overrides the default (full/source) variant
# Outputs:
#   Side effects: server image committed + version-tagged locally
# ---------------------------------------------------------------------------
build_server() {
  set_variant "${VARIANT:-}"
  resolve_version
  "${BUILDAH}" server
}


# ---------------------------------------------------------------------------
# build_tui()
#
# Description: composes just the opencode-tui image for the active variant.
# Globals:
#   VARIANT (string): optional; overrides the default (full/source) variant
# Outputs:
#   Side effects: tui image committed + version-tagged locally
# ---------------------------------------------------------------------------
build_tui() {
  set_variant "${VARIANT:-}"
  resolve_version
  "${BUILDAH}" tui
}


# ---------------------------------------------------------------------------
# distribute_images(<variant_tail>)
#
# Description: tags and pushes the composed server/tui images to the
#   registry. For the default variant: :latest, :<LATEST_VERSION> and
#   :<RESOLVED_HASH>. For a suffixed variant: :<tail> and :<tail>-<hash>,
#   keeping variant images fully distinct from the :latest default.
# Args:
#   $1  variant_tail (string): "" (default variant) or a suffix like
#       basic/full-binary/basic-binary
# Globals:
#   SERVER_IMG (string): server image namespace
#   TUI_IMG (string): tui image namespace
#   RESOLVED_HASH (string): hash tag; must be resolved beforehand
#   LATEST_VERSION (string): version tag for the default variant
# Outputs:
#   Side effects: registry pushes
# Returns:
#   Exits 1 if RESOLVED_HASH is unresolved
# ---------------------------------------------------------------------------
distribute_images() {
  variant_tail="$1"
  if [ -z "${RESOLVED_HASH}" ]; then
    error "Cannot distribute: could not resolve release tag hash."
    exit 1
  fi

  if [ -z "${variant_tail}" ]; then
    warn "==> Distributing Opencode [${RESOLVED_HASH}] container imagery (full stack)..."
    podman tag "${SERVER_IMG}:latest" "${SERVER_IMG}:${RESOLVED_HASH}"
    podman tag "${TUI_IMG}:latest" "${TUI_IMG}:${RESOLVED_HASH}"

    podman push "${SERVER_IMG}:latest"
    podman push "${SERVER_IMG}:${LATEST_VERSION}"
    podman push "${SERVER_IMG}:${RESOLVED_HASH}"

    podman push "${TUI_IMG}:latest"
    podman push "${TUI_IMG}:${LATEST_VERSION}"
    podman push "${TUI_IMG}:${RESOLVED_HASH}"
  else
    warn "==> Distributing Opencode [${RESOLVED_HASH}] container imagery (${variant_tail} stack)..."
    podman tag "${SERVER_IMG}:${variant_tail}" "${SERVER_IMG}:${variant_tail}-${RESOLVED_HASH}"
    podman tag "${TUI_IMG}:${variant_tail}" "${TUI_IMG}:${variant_tail}-${RESOLVED_HASH}"

    podman push "${SERVER_IMG}:${variant_tail}"
    podman push "${SERVER_IMG}:${variant_tail}-${RESOLVED_HASH}"

    podman push "${TUI_IMG}:${variant_tail}"
    podman push "${TUI_IMG}:${variant_tail}-${RESOLVED_HASH}"
  fi

  ok "✔ Opencode distribution loop completed!"
}


# ---------------------------------------------------------------------------
# Dispatch
#   compiler  - layer images for the default variant (cache warm-up)
#   server    - compose server image only
#   tui       - compose tui image only
#   publish   - build+compose then distribute, passing the variant to buildah
#   clean     - remove running jails and the final/composable ocbin images
# ---------------------------------------------------------------------------
case "${1:-}" in
compiler)
  build_layers
  ;;

server)
  build_server
  ;;

tui)
  build_tui
  ;;

publish)
  set_variant "${2:-}"
  resolve_version
  "${BUILDAH}" build
  distribute_images "${TAIL}"
  ;;

clean)
  warn "==> Dismantling Opencode execution runtimes and heavy compiler tracking layers..."
  podman rm -f ai-jail-opencode ai-jail-shell 2>/dev/null || true

  # word-splitting inside $(...) is intentional here, but shellcheck wants a
  # quoted word list; readarray into arrays and expand the explicit list
  readarray -t server_ids < <(podman images -q "${SERVER_IMG}")
  readarray -t tui_ids < <(podman images -q "${TUI_IMG}")
  readarray -t oc_source_ids < <(podman images -q "${REG_URL}/library/opencode/ocbin-source")
  readarray -t oc_binary_ids < <(podman images -q "${REG_URL}/library/opencode/ocbin-binary")
  podman rmi "${server_ids[@]:-}" "${tui_ids[@]:-}" "${oc_source_ids[@]:-}" "${oc_binary_ids[@]:-}" 2>/dev/null || true
  ok "✔ Opencode dismantling cycle completed safely. Layer images (base/pydex/pg/rust/uv/mcp) left in place."
  ;;

*)
  error "Error: Unknown opencode action target."
  exit 1
  ;;
esac