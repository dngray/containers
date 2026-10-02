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
# oc_generation_defaults()
#
# Description: fills in the per-generation defaults. Every version literal for
#   a generation lives here and nowhere else -- the binary-variant pin, the
#   resolve_version() fallback, and the OPENCODE_TAG the build falls back to
#   all read OC_DEFAULT_VERSION from this one table.
#
#   The two generations are not interchangeable upstream. Every v1 tag declares
#   "packageManager": "bun@1.3.14" and every v2 tag "bun@1.4.2", and both
#   enforce it in packages/script/src/index.ts. Note that guard relaxes the pin
#   to a caret range ("relax version requirement", verified at v2.0.22) and
#   tests semver.satisfies(bun, "^<declared>"), so ^1.3.14 ACCEPTS bun 1.4.2 --
#   it cannot be relied on to keep a v1 tree off a v2 toolchain. Do not go
#   probing that pairing; per the repo owner it builds and then crashes at
#   runtime. buildah-build.sh therefore asserts the tag's own packageManager
#   against the image it picked (see assert_bun_matches_tag there), and this
#   table is what it checks.
# Globals:
#   OPENCODE_API (string): generation; must already be set and validated
# Outputs:
#   Exports OC_DEFAULT_VERSION (string): pinned fallback for the generation
# Returns:
#   Exits 1 on an unknown OPENCODE_API
# ---------------------------------------------------------------------------
oc_generation_defaults() {
  case "${OPENCODE_API}" in
    v1) OC_DEFAULT_VERSION="1.18.34" ;;
    v2) OC_DEFAULT_VERSION="2.0.22" ;;
    *)
      error "Error: Unknown OPENCODE_API '${OPENCODE_API}' (expected v1 or v2)."
      exit 1
      ;;
  esac
  export OC_DEFAULT_VERSION
}


# ---------------------------------------------------------------------------
# latest_v2_tag()
#
# Description: newest v2 version, as a bare semver string with no v prefix.
#   v2 tags never appear in the GitHub releases endpoint -- releases/latest
#   tracks v1 (1.18.34) and releases/tags/v2.x.y is a 404, because no
#   workflow creates a Release for a v2 tag. The npm opencode-ai launcher is
#   no help either: its latest dist-tag is still 1.18.34, since v2 ships as
#   @opencode/cli-*. So the tag list itself is the only generation-aware
#   source. Read via ls-remote (no API token, no rate limit); peeled ^{}
#   refs are dropped and non-release tags (0.0.0-*, -rc*) are filtered so the
#   semver sort cannot pick one up.
# Outputs:
#   Prints the version to stdout; empty if the lookup fails
# ---------------------------------------------------------------------------
latest_v2_tag() {
  git ls-remote --tags https://github.com/anomalyco/opencode.git 'v2.*' 2>/dev/null |
    sed 's#.*refs/tags/##' |
    grep -v '\^{}' |
    grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' |
    sort -V |
    tail -1 |
    sed 's/^v//'
}


# ---------------------------------------------------------------------------
# resolve_version()
#
# Description: resolves and exports LATEST_VERSION (upstream stable release for
#   the active generation) and RESOLVED_HASH (short commit hash of
#   OPENCODE_TAG / that version).
#
#   v1 resolves through the GitHub releases endpoint. v2 cannot -- see
#   latest_v2_tag() -- so it sorts the tag list instead. Either way
#   LATEST_VERSION falls back to OC_DEFAULT_VERSION (the generation's pinned
#   release) when the lookup fails, so an unreachable network degrades to the
#   newest version we have actually validated rather than to a stale one.
#
#   RESOLVED_HASH tries the peeled tag, the plain tag, then HEAD. The peeled
#   form is what an annotated tag needs (v1.18.34 is one, v2.0.22 is not).
# Globals:
#   LATEST_VERSION (string): set if empty; exported for buildah-build.sh
#   RESOLVED_HASH (string): set if empty; exported for buildah-build.sh
#   OPENCODE_TAG (string): optional; read only for hash resolution
#   OC_DEFAULT_VERSION (string): per-generation fallback; see
#       oc_generation_defaults()
# Outputs:
#   Exports LATEST_VERSION and RESOLVED_HASH
# ---------------------------------------------------------------------------
resolve_version() {
  if [ -z "${LATEST_VERSION:-}" ]; then
    case "${OPENCODE_API}" in
      v1)
        info "==> Querying upstream repository for latest stable release tag..."
        LATEST_VERSION=$(curl -s "https://api.github.com/repos/anomalyco/opencode/releases/latest" |
          jq -r .tag_name | sed 's/^v//' || true)
        ;;
      *)
        info "==> Querying upstream repository for latest v2 tag..."
        LATEST_VERSION=$(latest_v2_tag)
        ;;
    esac

    if [ -z "$LATEST_VERSION" ]; then
      warn " Could not fetch dynamic tags. Falling back to pinned baseline v${OC_DEFAULT_VERSION}..."
      LATEST_VERSION="${OC_DEFAULT_VERSION}"
    else
      ok " Found current ${OPENCODE_API} release version: ${LATEST_VERSION}"
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
#   It also resolves OPENCODE_API, which is orthogonal to the variant name:
#   the API generation picks the v1/v2 config, SELinux policy and launcher
#   wiring, not a different build. v2 is the default; v1 stays selectable and
#   shares this pipeline, it just resolves its own version/bun/channel.
# Args:
#   $1  variant_name (string): "" | full | binary | full-binary | basic |
#       basic-binary
# Globals:
#   OPENCODE_TAG (string): set to v<OC_DEFAULT_VERSION> for binary variants
#       when unset
#   OPENCODE_API (string): set to v2 when unset
# Outputs:
#   Exports STACK, SRC, TAIL, OPENCODE_TAG, OPENCODE_API and
#       OC_DEFAULT_VERSION
# Returns:
#   Exits 1 on unknown variant names or unknown OPENCODE_API values
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
      ;;
    *)
      error "Error: Unknown publish variant '$1' (expected full, full-binary, basic, basic-binary)."
      exit 1
      ;;
  esac

  # Resolve the generation BEFORE the pin: the pin is per-generation, so it has
  # to come out of the same table every other default does.
  OPENCODE_API="${OPENCODE_API:-v2}"
  case "${OPENCODE_API}" in
    v1 | v2) ;;
    *)
      error "Error: Unknown OPENCODE_API '${OPENCODE_API}' (expected v1 or v2)."
      exit 1
      ;;
  esac
  oc_generation_defaults

  # The pin is a sanity guard against a moved/renamed tag: binary variants
  # download that exact release rather than whatever LATEST_VERSION resolved
  # to. Source variants are unaffected -- they build the resolved tag.
  if [ "${SRC}" = binary ]; then
    OPENCODE_TAG="${OPENCODE_TAG:-v${OC_DEFAULT_VERSION}}"
  fi

  export STACK SRC TAIL OPENCODE_TAG OPENCODE_API
  info "==> Variant: stack=${STACK} src=${SRC} api=${OPENCODE_API} tag=${OPENCODE_TAG:-resolved} tail=${TAIL:-latest}"
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
#   layers    - layer images for the default variant (cache warm-up)
#   server    - compose server image only
#   tui       - compose tui image only
#   publish   - build+compose then distribute, passing the variant to buildah
#   clean     - remove running jails and the final/composable ocbin images
# ---------------------------------------------------------------------------
case "${1:-}" in
layers)
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
  ok "✔ Opencode dismantling cycle completed safely. Layer images (base/pydex/pg/rust/uv/gobin/mcp/devtools) left in place."
  ;;

*)
  error "Error: Unknown opencode action target."
  exit 1
  ;;
esac