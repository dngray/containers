#!/bin/bash
# apps/opencode/buildah-build.sh
#
# Imperative buildah pipeline for the opencode container catalog.
#
# ---------------------------------------------------------------------------
# Model
# ---------------------------------------------------------------------------
# Every expensive / deterministic step is built ONCE as its own committed
# layer image and pushed to ${REG_URL}/library/opencode/... Compose of a
# runnable variant is then nothing more than "picking" which layer images
# to merge, so an opencode tag bump only rebuilds the ocbin layer (and the
# finals) -- it NEVER recompiles Python, lean-ctx, or pgvector.
#
# Layer  catalog (all under "${REG_URL}/library/opencode"):
#   base          v1                Debian runtime + tools + opencode user
#   tui-base      v1                slim Debian for the attach-only TUI
#   pydex         <PYVER>           sigstore-verified Python-from-source; the
#                                   image's ONLY python (see UV_PYTHON below)
#   ocbin-source  <hash>            opencode compiled from source (bun/turbo)
#   ocbin-binary  <hash>            pinned upstream, sha256-verified release
#   pgassets      <PGVER>           pgclient + pgvector (payload staging dir)
#   rusttools     latest            lean-ctx built from crates.io
#   gobin         latest            Go CLI tools (yq, gomplate, age) + hadolint release binary
#   uvbin         latest            uv / uvx binaries on a scratch rootfs
#   mcp           latest            MCP/LSP tools payload in /home/opencode/.local
#   ansible       latest            pinned uv-managed ansible-core + Galaxy
#                                   collections, staged in /ansible-layer
#   devtools      latest            agent validation/debug toolchain, merged from
#                                   the layer's own /usr,/etc,/var
#
# Variant  matrix (STACK x SRC) -> which layers final images pick:
#   full + source   pydex + mcp + ansible + pgassets + rusttools + ocbin-source (default)
#   full + binary   pydex + mcp + ansible + pgassets + rusttools + ocbin-binary
#   basic + source  pydex + mcp + ansible                  + ocbin-source
#   basic + binary  pydex + mcp + ansible                  + ocbin-binary
# full adds postgres and lean-ctx over basic; that is the only difference.
# Every variant also merges uvbin, gobin and devtools. The tui image is
# tui-base + ocbin (attach-only, so it deliberately gets none of them).
#
# Python topology: every variant builds FROM pydex, so the image has one
# Python and it is ${PYVER}. Debian's python3 still rides along in base
# because build_pydex needs it to bootstrap the sigstore venv, but nothing
# resolves to it at runtime. Do not add python3-* apt packages anywhere --
# they are built for Debian's 3.13 and are useless to a 3.14 venv. Python
# tooling goes in through uv with UV_PYTHON pinned to pydex, otherwise uv
# downloads and uses a managed interpreter of its own (its python-preference
# default is "managed") and the venvs stop being reproducible.
#
# That decoy is 3.13.x and it cannot be deleted: on trixie apt and dpkg are
# themselves python3 programs, so removing it breaks the package manager in
# the image. What keeps the agent honest is ordering -- python_path_prefix puts
# /opt/python-${PYVER}/bin ahead of /usr/bin, and /usr/local/bin/python3 is a
# symlink to the same -- plus the build-time import assertion in build_ansible.
# A tool that ignores both (an absolute path, a hardcoded #!/usr/bin/python3
# shebang from a Debian package, a venv it did not expect) still lands on the
# wrong one, so anything the agent runs should be resolved by name off PATH.
#
# Why devtools is a layer and not more build_base packages: `ensure` short-
# circuits on image presence, and the finals are `buildah from ${PYDEX_IMG}`,
# so anything appended to build_base only reaches them after base AND pydex are
# both force-removed and rebuilt (pydex alone is ~2.4G). A separate layer keeps
# the validation toolchain independent of that chain, exactly like the old
# yq-only layer did.
#
# opencode.json is copied verbatim from build/opencode/config/<api>/opencode.jsonc
# (the full-stack config); the basic stack drops the lean_ctx entry via jq.
# OPENCODE_API picks the file: v2 discovers opencode.json/.jsonc in the same
# global config dir and keeps `lsp` as-is, so v2's copy is currently identical
# to v1's; only the mcp server map is destined to move under `mcp.servers`.
#
# OPENCODE_API (v1 | v2, default v1) is a third, orthogonal dimension: the
# STACK x SRC matrix above picks the layer set, while OPENCODE_API picks the
# API generation's config, SELinux policy and launcher wiring. It is
# deliberately NOT part of the variant name, so the image set stays the same
# for both generations and the variant selector is unchanged -- the fortress
# launcher carries it as its own trailing [v1|v2] argument instead, defaulting
# to v1.
#
# config_source() reads it to pick build/opencode/config/$OPENCODE_API, and the
# fortress SELinux policy is versioned the same way. v2 has no image yet, so
# nothing here builds one: generation only selects among pre-existing inputs,
# and the launcher refuses v2 until a v2 image exists. Note that the image tag
# does not encode the generation -- as upstream does, the version tag carries
# it (1.18.33 is v1, 2.0.18 is v2) and :latest is a single mutable pointer.
#
# ---------------------------------------------------------------------------
# Environment (set by apps/opencode/opencode.sh or lib/cli.sh)
# ---------------------------------------------------------------------------
#   REQUIRED  REG_URL       private registry host
#   REQUIRED  RESOLVED_HASH 7-char tag hash that tags/shames ocbin layers
#   REQUIRED  OPENCODE_TAG  git tag / release tag, default v${LATEST_VERSION}
#   OPTIONAL  LATEST_VERSION, HOST_UID, HOST_GID (lib/cli.sh), STACK, SRC,
#             TAIL, OPENCODE_API (v1 | v2, default v1), BUILD_JOBS (parallelism,
#             default nproc),
#             PYTHON_VERSION (default 3.14.7), PGVECTOR_VERSION (default 0.8.2),
#             HADOLINT_VERSION (default v2.15.1), GOMPLATE_VERSION (default
#             v5.2.0), AGE_VERSION (default v1.3.2, covers age + age-keygen +
#             age-plugin-batchpass), NO_PUSH=1 (commit locally without push)
#
# ---------------------------------------------------------------------------
# Notes
# ---------------------------------------------------------------------------
#   * `buildah mount` needs an unshared user+mount namespace when running
#     rootless, so the script re-execs itself once under `buildah unshare`.
#   * The host cache bind-mounts rely on SELinux type `container_file_t` so the
#     build-time `container_t` domain can manage them (see selinux_cache_guard
#     below). The fortress policy labels $HOME/{src,workspace} as fortress_src_t,
#     so under Enforcing the build cache needs an fcontext exception; the runtime
#     label comes from the selinux-fortress policy
#     (`--security-opt label=type:fortress_agent_t` in apps/fortress/fortress-exec).
#
# Subcommands: layers | server | tui | build

set -euo pipefail

# shellcheck disable=SC1007  # repo-convention empty assignment in CDPATH= cd
REPO_ROOT=$(CDPATH= cd "$(dirname "$0")/../.." && pwd)
. "${REPO_ROOT}/lib/cli.sh"

# Inside `buildah unshare` the invoking user is remapped to namespace root, so
# the re-sourced lib/cli.sh would recompute HOST_UID/HOST_GID as 0. Stash the
# host values in the first invocation and restore them in the re-exec so build
# layers create the `opencode` user with the host uid/gid.
if [ -n "${_BUILDAH_UNSHARED:-}" ] && [ -n "${_HOST_UID_FOR_UNSHARE:-}" ]; then
  HOST_UID="${_HOST_UID_FOR_UNSHARE}"
  HOST_GID="${_HOST_GID_FOR_UNSHARE}"
  export HOST_UID HOST_GID
fi

# merge_payload() needs `buildah mount`, which in rootless mode requires an
# unshared user+mount namespace. Re-exec under `buildah unshare` exactly once
# (the marker env prevents a re-entry loop; root invocations skip this).
if [ "$(id -u)" -ne 0 ] && [ -z "${_BUILDAH_UNSHARED:-}" ]; then
  export _BUILDAH_UNSHARED=1
  export _HOST_UID_FOR_UNSHARE="${HOST_UID}" _HOST_GID_FOR_UNSHARE="${HOST_GID}"
  exec buildah unshare "$0" "$@"
fi

# ---------------------------------------------------------------------------
# Globals
# ---------------------------------------------------------------------------
NS="${REG_URL}/library/opencode"          # namespace for every layer/final image
CACHE="${REPO_ROOT}/build/opencode/cache" # host-side build cache (source, tarballs, debs)
DL="${CACHE}/opencode_dl"                 # downloaded opencode release tarballs
STAGE="${CACHE}/buildah_stage"            # scratch area for compose-time files

PYVER="${PYTHON_VERSION:-3.14.7}"
PGVER="${PGVECTOR_VERSION:-0.8.2}"
HADOLINT_VERSION="${HADOLINT_VERSION:-v2.15.1}"
GOMPLATE_VERSION="${GOMPLATE_VERSION:-v5.2.0}"
# age, age-keygen and age-plugin-batchpass all live in the ONE module
# filippo.io/age -- the plugin is cmd/age-plugin-batchpass inside the same
# repo/tag, not a separate module -- so a single pin covers all three and
# version skew between them is impossible. Pinned rather than @latest for the
# same reason gomplate is: a floating age would silently change the agent's
# crypto under an unchanged :latest layer tag. @latest currently resolves to
# v1.3.2, so pinning it changes nothing today.
AGE_VERSION="${AGE_VERSION:-v1.3.2}"
BUILD_JOBS="${BUILD_JOBS:-$(nproc)}"

# Ansible validation environment. Pinned rather than floating: the agent uses
# this to validate its own infrastructure work, so a silent upstream jump would
# change validation results without any image change to explain it.
# ansible-core is installed DIRECTLY, not as a dependency of the community
# `ansible` metapackage, and not as a uv tool. The metapackage declares exactly
# one console script -- the `ansible-community` info stub -- while the ten real
# CLIs (ansible, ansible-playbook, ansible-galaxy, ansible-doc, ...) belong to
# ansible-core, so the layer used to die on a missing ansible-galaxy before it
# could bake its collections. A tool env was the wrong fix for a second reason:
# it is invisible to the interpreter `python3` resolves to, so `import ansible`
# and its Jinja2/PyYAML deps stayed unresolved for every ad-hoc interpreter
# call and for the LSP. So ansible-core goes into the pydex python itself
# (uv pip install --system, not pip: UV_PYTHON pins the target), the ten CLIs
# come from the bin dir that is first on PATH, and the install run asserts the
# import. That is also the cheaper of the two shapes -- the alternative is a
# third copy of core, since the lint env carries its own. ansible-lint 26.9.0
# requires ansible-core>=2.16.19,!=2.17.*, so it resolves the same core.
# The metapackage's own bundled collections were never usable either: they sit
# in the tool venv's site-packages, which ANSIBLE_COLLECTIONS_PATH (set to the
# staged payload in compose_server) does not search. Dropping it costs 51MB and
# that one stub; the collections the agent actually gets are the two baked
# below.
ANSIBLE_CORE_VERSION="${ANSIBLE_CORE_VERSION:-2.21.4}"
ANSIBLE_LINT_VERSION="${ANSIBLE_LINT_VERSION:-26.9.0}"
ANSIBLE_POSIX_VERSION="${ANSIBLE_POSIX_VERSION:-2.2.2}"
ANSIBLE_COMMUNITY_GENERAL_VERSION="${ANSIBLE_COMMUNITY_GENERAL_VERSION:-13.4.0}"

# ---------------------------------------------------------------------------
# Per-generation constants.
#
# The single source of truth for what differs between the v1 and v2 API
# generations. Each generation's version literal lives here and nowhere else;
# the OPENCODE_TAG fallback, the bun toolchain, the baked release channel and
# both ocbin builders all read this table.
#
# OC_BUN_IMAGE is not a preference, it is a hard requirement. Every v1 tag
# declares "packageManager": "bun@1.3.14" and every v2 tag "bun@1.4.2", and both
# generations throw from packages/script/src/index.ts when the running bun
# does not satisfy the declared range. Upstream's own CI agrees -- publish.yml
# pins bun-version 1.4.2 for the v2 CLI build.
#
# Upstream's guard cannot catch a cross-generation pairing on its own. At
# v2.0.22 it relaxes the declared pin to a caret range
# (packages/script/src/index.ts, comment "relax version requirement") and
# tests semver.satisfies(bun, "^<declared>"), so ^1.3.14 admits 1.4.2 -- a v1
# tree does not reject the v2 toolchain.
#
# Do NOT go looking for that failure mode. Per the repo owner, building a v1
# tree on bun 1.4+ runs to completion and then crashes at runtime with a
# confusing error; that is their report from having hit it, not something
# reproduced here, and reproducing it would cost a full build to learn nothing
# this table cannot state. assert_bun_matches_tag() exists so the pairing is
# checked up front instead of discovered at runtime: it compares the
# checked-out tag's OWN declared pin against the image chosen here.
# ---------------------------------------------------------------------------
OPENCODE_API="${OPENCODE_API:-v2}"
case "${OPENCODE_API}" in
  v1)
    OC_DEFAULT_VERSION="1.18.34"
    OC_CHANNEL="prod"
    OC_BUN_IMAGE="docker.io/oven/bun:1.3.14-debian"
    ;;
  v2)
    OC_DEFAULT_VERSION="2.0.22"
    # MUST be a channel whose defaultPort() is 0xc0de (49374). service-config.ts
    # returns 0xc0de only for latest|dev|beta|next and otherwise HASHES the
    # channel name into 10000-59999, so baking v1's "prod" here would silently
    # move the server off the port the SELinux policy labels and off the one
    # the fortress probes.
    OC_CHANNEL="latest"
    OC_BUN_IMAGE="docker.io/oven/bun:1.4.2-debian"
    ;;
  *)
    error "Error: Unknown OPENCODE_API '${OPENCODE_API}' (expected v1 or v2)."
    exit 1
    ;;
esac

: "${OPENCODE_TAG:=v${LATEST_VERSION:-$OC_DEFAULT_VERSION}}"
: "${RESOLVED_HASH:?resolve_version must run first}"

BASE_IMG="${NS}/base:v1"
TUI_BASE_IMG="${NS}/tui-base:v1"
PYDEX_IMG="${NS}/pydex:${PYVER}"
PGA_IMG="${NS}/pgassets:${PGVER}"
RUST_IMG="${NS}/rusttools:latest"
GOBIN_IMG="${NS}/gobin:latest"
UVBIN_IMG="${NS}/uvbin:latest"
MCP_IMG="${NS}/mcp:latest"
DEVTOOLS_IMG="${NS}/devtools:latest"
ANSIBLE_IMG="${NS}/ansible:latest"
OC_SRC_IMG="${NS}/ocbin-source:${RESOLVED_HASH}"
OC_BIN_IMG="${NS}/ocbin-binary:${RESOLVED_HASH}"
SERVER_IMG="${NS}/opencode-server"
TUI_IMG="${NS}/opencode-tui"

# apt tweaks: keep downloaded debs and redirect them onto the host cache so
# every build layer shares one package cache (bind-mounted at /mnt/host_cache).
APTDROP='rm -f /etc/apt/apt.conf.d/*clean*; printf "APT::Keep-Downloaded-Packages \"true\";\n" > /etc/apt/apt.conf.d/01keep-debs; printf "Dir::Cache::archives \"/mnt/host_cache/apt_cache\";\n" >> /etc/apt/apt.conf.d/01keep-debs'

mkdir -p "${DL}" "${STAGE}" "${CACHE}/apt_cache/partial"

# ---------------------------------------------------------------------------
# selinux_cache_guard()
#
# Description: fails fast when SELinux inhibits the build cache. The fortress
#   policy labels $HOME/{src,workspace}(/.*)? as fortress_src_t, a type the
#   build-time container_t domain may not read/write (only the runtime
#   fortress_agent_t domain can). A cache under the repo therefore needs the
#   container_file_t type; otherwise apt hits AVC denials on the /mnt/host_cache
#   bind mount ("E: Unable to lock directory .../apt_cache/", exit status 100).
#   Relabling needs root, so this only diagnoses + prints the fix.
# Globals:
#   CACHE (string): host cache dir; must resolve to container_file_t
# Outputs:
#   Exits 1 with the remediation snippet when the label is wrong
# ---------------------------------------------------------------------------
selinux_cache_guard() {
  [ "$(getenforce 2>/dev/null || echo Disabled)" = Enforcing ] || return 0
  cache_label=$(stat -c '%C' "${CACHE}" 2>/dev/null || true)
  case "${cache_label}" in
  *fortress_src_t*)
    error "SELinux: ${CACHE} is labeled fortress_src_t, which container_t (the build domain) cannot access."
    item "Relabel the build cache as container_file_t, then re-run:"
    info "  sudo semanage fcontext -a -t container_file_t '${REPO_ROOT}/build/opencode/cache(/.*)?'"
    info "  sudo restorecon -RFv ${REPO_ROOT}/build/opencode/cache"
    exit 1
    ;;
  esac
}
selinux_cache_guard

# ---------------------------------------------------------------------------
# img_exists(<image>)
#
# Description: true if an image with that name (or ID) already exists in the
#   local buildah store. Local existence is the layer "cache".
# Args:
#   $1  image (string): name, with tag, to look up
# Returns:
#   0 if the image exists, 1 otherwise.
# ---------------------------------------------------------------------------
img_exists() {
  [ -n "$(buildah images -q "$1" 2>/dev/null)" ]
}

# ---------------------------------------------------------------------------
# ensure(<layer_name>, <image>)
#
# Description: idempotent layer build+push. If <image> is already present
#   locally it is reused; otherwise the matching build_<layer_name> function
#   runs and the result is pushed to the registry (unless NO_PUSH=1).
# Args:
#   $1  layer_name (string): basename selecting build_${layer_name}()
#   $2  image (string): fully-qualified image name to commit/push
# Globals:
#   BUILD_JOBS (int): parallelism, read for the build log line
#   NO_PUSH (int): "1" commits locally without a registry push
# Outputs:
#   None directly; side effect is a new layer image and an optional push
# ---------------------------------------------------------------------------
ensure() {
  if img_exists "$2"; then
    ok " Layer ready: $1 ($2)"
  else
    info "==> Building layer: $1 ($2) [BUILD_JOBS=${BUILD_JOBS}]"
    "build_${1}"
    if [ "${NO_PUSH:-0}" = 1 ]; then
      ok " Committed locally (NO_PUSH=1): $2"
    else
      buildah push "$2"
      ok " Pushed layer: $2"
    fi
  fi
}

# ---------------------------------------------------------------------------
# ocbin_for(<src>)
#
# Description: returns the ocbin layer image matching the requested opencode
#   provenance.
# Args:
#   $1  src (string): "binary" (pinned, sha256-verified release) or
#       "source" (compiled)
# Globals:
#   OC_BIN_IMG (string): image name returned for src=binary
#   OC_SRC_IMG (string): image name returned for src=source
# Returns:
#   Prints the chosen ocbin image name to stdout
# ---------------------------------------------------------------------------
ocbin_for() {
  [ "$1" = binary ] && echo "${OC_BIN_IMG}" || echo "${OC_SRC_IMG}"
}

# ---------------------------------------------------------------------------
# assert_bun_matches_tag(<checkout_dir>)
#
# Description: fails the build when the pinned tag's own bun declaration
#   disagrees with the bun image the generation table selected. Reads
#   packageManager straight out of the checked-out tree, so it validates the
#   ACTUAL source about to be compiled rather than a remembered version.
#
#   Upstream's own guard cannot catch the pairing it looks like it catches: at
#   v2.0.22, packages/script/src/index.ts relaxes the declared pin to a caret
#   range ("relax version requirement") and tests
#   semver.satisfies(bun, "^<declared>"), so ^1.3.14 is satisfied by bun 1.4.2
#   and a v1 tree does not reject the v2 toolchain. Per the repo owner, such a
#   build runs to completion and then crashes at runtime -- their report, not
#   something reproduced here. Here it stops before the compile instead of after
#   it.
#
#   Matched on the full x.y.z (a declared 1.4.2 accepts a 1.4.2.x image, not
#   1.4.3), so a bun patch bump has to be a deliberate edit on both sides.
# Args:
#   $1  checkout_dir (string): path to the checked-out opencode source tree
# Globals:
#   OC_BUN_IMAGE (string): image the generation table selected
# Outputs:
#   Exits 1 with both versions named when they disagree
# ---------------------------------------------------------------------------
assert_bun_matches_tag() {
  local checkout_dir="$1" want declared
  want=${OC_BUN_IMAGE##*:}   # 1.4.2-debian
  want=${want%-debian}       # 1.4.2
  declared=$(jq -r '.packageManager // "" | split("@")[1] // ""' \
    "${checkout_dir}/package.json" 2>/dev/null || true)

  if [ -z "$declared" ]; then
    error "No packageManager field in ${checkout_dir}/package.json; cannot verify the bun toolchain."
    info "  A v2 tree under packages/opencode has moved; check the tag is not a v1/v2 mix."
    return 1
  fi
  case "$declared" in
    "$want" | "$want".*) ;;
    *)
      error "bun toolchain mismatch: tag ${OPENCODE_TAG} declares packageManager bun@${declared}," \
        "but generation ${OPENCODE_API} selects ${OC_BUN_IMAGE} (bun ${want})."
      info "  Upstream's own ^${declared} guard accepts bun ${want}, so this would not be caught upstream."
      info "  Build this tag with the bun it declares, or change OC_BUN_IMAGE in the generation table."
      return 1
      ;;
  esac
  ok " bun toolchain matches tag: bun@${declared} (${OC_BUN_IMAGE})"
}

# ---------------------------------------------------------------------------
# build_base()
#
# Description: Debian runtime foundation for the server. Installs the tool
#   layer for both stacks, seeds the repo CA bundle, and creates the
#   `opencode` user/workspace reflecting the host uid/gid, then commits.
# Globals:
#   HOST_UID (int): `opencode` user uid, from lib/cli.sh
#   HOST_GID (int): group gid for the opencode user, from lib/cli.sh
#   CACHE (string): host cache dir bind-mounted at /mnt/host_cache
#   APTDROP (string): apt snippet pinning debs to the host cache
#   BASE_IMG (string): image name committed when complete
# Outputs:
#   Commits ${BASE_IMG}
# ---------------------------------------------------------------------------
build_base() {
  local container
  container=$(buildah from docker.io/library/debian:trixie-slim)
  # python3/python3-venv are Debian's 3.13 and stay ONLY to bootstrap
  # build_pydex's sigstore venv -- they are not the image's Python and nothing
  # at runtime resolves to them. Do not drop them, and do not add python3-*
  # library packages here: those are built for 3.13 and useless to pydex.
  buildah config --env DEBIAN_FRONTEND=noninteractive "$container"
  buildah run --volume "${CACHE}:/mnt/host_cache" "$container" -- bash -ec "
    set -e
    mkdir -p /mnt/host_cache/apt_cache/partial
    ${APTDROP}
    apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl gcc libc6-dev coreutils fd-find findutils fzf gawk \
      git jq ripgrep sed util-linux shellcheck nodejs npm \
      python3 python3-venv
    ln -sf \"\$(command -v fdfind)\" /usr/local/bin/fd
  "
  buildah copy "$container" "${REPO_ROOT}/build/opencode/roots.pem" /usr/local/share/ca-certificates/roots.crt
  buildah run "$container" -- bash -ec '
    chmod 644 /usr/local/share/ca-certificates/roots.crt && update-ca-certificates
  '
  buildah config --env CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt "$container"
  buildah config --env SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt "$container"
  buildah config --env HOME=/home/opencode "$container"
  buildah run "$container" -- bash -ec "
    groupadd -f -g ${HOST_GID} opencode
    useradd -m -u ${HOST_UID} -g 0 -s /bin/bash opencode
    mkdir -p /home/opencode/workspace
    chown -R ${HOST_UID}:0 /home/opencode
  "
  buildah commit --rm "$container" "${BASE_IMG}"
}

# ---------------------------------------------------------------------------
# build_tui_base()
#
# Description: minimal Debian for the attach-only TUI client (no compilers,
#   no node, just the CA trust and the opencode xdg state dirs).
# Globals:
#   HOST_UID (int): `opencode` user uid, from lib/cli.sh
#   HOST_GID (int): group gid for the opencode user, from lib/cli.sh
#   CACHE (string): host cache dir bind-mounted at /mnt/host_cache
#   APTDROP (string): apt snippet pinning debs to the host cache
#   TUI_BASE_IMG (string): image name committed when complete
# Outputs:
#   Commits ${TUI_BASE_IMG}
# ---------------------------------------------------------------------------
build_tui_base() {
  local container
  container=$(buildah from docker.io/library/debian:trixie-slim)
  buildah config --env DEBIAN_FRONTEND=noninteractive "$container"
  buildah run --volume "${CACHE}:/mnt/host_cache" "$container" -- bash -ec "
    set -e
    mkdir -p /mnt/host_cache/apt_cache/partial
    ${APTDROP}
    apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl coreutils jq git
  "
  buildah copy "$container" "${REPO_ROOT}/build/opencode/roots.pem" /usr/local/share/ca-certificates/roots.crt
  buildah run "$container" -- bash -ec '
    chmod 644 /usr/local/share/ca-certificates/roots.crt && update-ca-certificates
  '
  buildah config --env CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt "$container"
  buildah config --env SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt "$container"
  buildah config --env HOME=/home/opencode "$container"
  buildah run "$container" -- bash -ec "
    groupadd -f -g ${HOST_GID} opencode
    useradd -m -u ${HOST_UID} -g 0 -s /bin/bash opencode
    mkdir -p /home/opencode/workspace /home/opencode/.config/opencode \
      /home/opencode/.local/share/opencode /home/opencode/.local/state/opencode \
      /home/opencode/.cache/opencode
    chown -R ${HOST_UID}:0 /home/opencode
  "
  buildah commit --rm "$container" "${TUI_BASE_IMG}"
}

# ---------------------------------------------------------------------------
# build_pydex()
#
# Description: installs CPython into /opt/python-<PYVER> from a sigstore
#   VERIFIED release tarball (identity hugo@python.org, GitHub OIDC) with
#   optimizations + LTO + experimental JIT, then commits. The tarball and
#   provenance bundle are cached on the host so verification only happens
#   once. Requires clang-19/llvm-19 for the JIT build. The run is root with
#   HOME=/root exported inside it: the image env carries the agent's HOME, and
#   a root run must never write into it (see the note in the body).
# Globals:
#   PYVER (string): CPython version; selects tarball, /opt prefix and tag
#   BUILD_JOBS (int): parallelism for the CPython make
#   CACHE (string): host cache dir; python tarball + sigstore bundle cached
#   PYDEX_IMG (string): image name committed when complete
# Outputs:
#   Commits ${PYDEX_IMG}; adds /usr/local/bin/python3 + python<PYVER> symlinks
# ---------------------------------------------------------------------------
build_pydex() {
  local container python_tarball python_sigstore_bundle
  container=$(buildah from "${BASE_IMG}")
  python_tarball="Python-${PYVER}.tar.xz"
  python_sigstore_bundle="Python-${PYVER}.tar.xz.sigstore"
  buildah run --volume "${CACHE}:/mnt/host_cache" "$container" -- bash -ec "
    set -e
    # This run is root, and base bakes HOME=/home/opencode into the image env,
    # so the sigstore bootstrap's pip writes its wheel cache into the agent's
    # home AS ROOT: /home/opencode/.cache ships root-owned inside the pydex
    # layer, and every layer built on pydex then dies installing anything as
    # --user opencode (uv: \"Failed to initialize cache at
    # /home/opencode/.cache/uv\"). Point root's HOME at root's own home for
    # this run; the committed image keeps the agent's HOME, so this stays an
    # export inside the run rather than a buildah config --env.
    export HOME=/root
    apt-get update && apt-get install -y --no-install-recommends \
      build-essential libssl-dev zlib1g-dev libncurses5-dev libreadline-dev \
      libsqlite3-dev liblzma-dev libffi-dev clang-19 llvm-19 llvm-19-dev
    python3 -m venv /opt/sigstore-venv
    /opt/sigstore-venv/bin/pip install sigstore
    if [ -f /mnt/host_cache/python_src/${python_tarball} ]; then
      cp /mnt/host_cache/python_src/${python_tarball} /tmp/
      cp /mnt/host_cache/python_src/${python_sigstore_bundle} /tmp/
    else
      curl -fL -o /tmp/${python_tarball} https://www.python.org/ftp/python/${PYVER}/${python_tarball}
      curl -fL -o /tmp/${python_sigstore_bundle} https://www.python.org/ftp/python/${PYVER}/${python_sigstore_bundle}
      mkdir -p /mnt/host_cache/python_src
      cp /tmp/${python_tarball} /tmp/${python_sigstore_bundle} /mnt/host_cache/python_src/
    fi
    cd /tmp
    /opt/sigstore-venv/bin/python3 -m sigstore verify identity \
      --bundle /tmp/${python_sigstore_bundle} \
      --cert-identity hugo@python.org \
      --cert-oidc-issuer https://github.com/login/oauth \
      /tmp/${python_tarball}
    tar -xf /tmp/${python_tarball}
    cd /tmp/Python-${PYVER}
    ./configure --enable-optimizations --with-lto --enable-experimental-jit \
      --prefix=/opt/python-${PYVER}
    make -j${BUILD_JOBS}
    make install
    cd /tmp && rm -rf Python-${PYVER} /tmp/${python_tarball} /tmp/${python_sigstore_bundle}
    rm -rf /home/opencode/.cache
  "
  buildah run "$container" -- bash -ec "
    ln -sf /opt/python-${PYVER}/bin/python3 /usr/local/bin/python3
    ln -sf /opt/python-${PYVER}/bin/python3 /usr/local/bin/python${PYVER}
  "
  buildah commit --rm "$container" "${PYDEX_IMG}"
}

# ---------------------------------------------------------------------------
# build_ocbin_source()
#
# Description: builds the opencode binary from the pinned git tag using the
#   generation's pinned bun base image. The source tree and bun dependency
#   cache live on the host so repeat runs are incremental (git fetch + no-op
#   install).
#
#   Three buildah run steps, not one, because the toolchain check has to land
#   BETWEEN the checkout and the expensive part. The checkout lands in the host
#   cache (bind-mounted), so assert_bun_matches_tag can read the tag's own
#   package.json from here. Upstream's caret-range guard does not stop a
#   cross-generation pairing, and per the repo owner such a build finishes and
#   then crashes at runtime -- so no amount of log-reading after the fact fixes
#   the twenty minutes it cost.
# Globals:
#   OPENCODE_TAG (string): git tag to build from
#   LATEST_VERSION (string): version baked into the binary at build time
#   OC_BUN_IMAGE (string): generation's bun base image
#   OC_CHANNEL (string): release channel baked into the binary (see the
#       generation table: v2 must bake "latest" or the server port hashes)
#   BUILD_JOBS (int): bun/turbo concurrency
#   CACHE (string): host cache dir; source tree + bun store cached
#   OC_SRC_IMG (string): image name committed when complete
# Outputs:
#   Commits ${OC_SRC_IMG} with /usr/local/bin/opencode
# ---------------------------------------------------------------------------
build_ocbin_source() {
  local container release_tag
  release_tag="${OPENCODE_TAG}"
  ocbin_source_layout
  container=$(buildah from "${OC_BUN_IMAGE}")
  buildah config --env HOME=/mnt/host_cache/bun "$container"
  buildah config --env NODE_OPTIONS=--max-old-space-size=4096 "$container"

  # 1. toolchain + source checkout (cheap; nothing compiled yet)
  buildah run --volume "${CACHE}:/mnt/host_cache" "$container" -- bash -ec "
    set -e
    export HOME=/mnt/host_cache/bun
    mkdir -p /mnt/host_cache/opencode_src
    apt-get update && apt-get install -y --no-install-recommends \
      git curl ca-certificates jq ca-certificates
    cd /mnt/host_cache/opencode_src
    if [ ! -d repo/.git ]; then
      git clone --branch ${release_tag} --depth 1 \\
        https://github.com/anomalyco/opencode.git repo
    else
      cd repo
      git fetch --tags --depth 1 origin ${release_tag}
      git checkout FETCH_HEAD
      cd ..
    fi
    rm -rf /src/opencode
    mkdir -p /src/opencode
    cp -r /mnt/host_cache/opencode_src/repo/. /src/opencode/
  "

  # 2. fail fast if the tag wants a different bun than the generation table gave us
  assert_bun_matches_tag "${CACHE}/opencode_src/repo"

  # 3. install + build. OPENCODE_VERSION and OPENCODE_CHANNEL are the same two
  #    variables both generations read for the baked-in version/channel; the
  #    channel is what decides the server port, so it comes from the table
  #    rather than being written here.
  #
  #    The cache volume is re-mounted here as well as in step 1: HOME is
  #    /mnt/host_cache/bun, so without --volume bun's module cache would live on
  #    the container's throwaway layer and every build would re-download the
  #    whole dependency tree.
  buildah run --volume "${CACHE}:/mnt/host_cache" "$container" -- bash -ec "
    set -e
    export HOME=/mnt/host_cache/bun
    cd /src/opencode
    export OPENCODE_VERSION=\"${LATEST_VERSION:-$OC_DEFAULT_VERSION}\"
    export OPENCODE_CHANNEL=${OC_CHANNEL}
    export HUSKY=0
    export BUN_CONFIG_MAX_WORKERS=${BUILD_JOBS}
    $(ocbin_source_install_cmds)
    $(ocbin_source_build_cmds)
    chmod +x ${OC_SRC_OUT}
    cp ${OC_SRC_OUT} /usr/local/bin/opencode
    rm -rf /src/opencode
  "
  buildah commit --rm "$container" "${OC_SRC_IMG}"
}

# ---------------------------------------------------------------------------
# ocbin_source_layout()
#
# Description: sets OC_SRC_OUT, the in-tree path where the build leaves the
#   compiled binary. Differs per generation because the package layout does:
#   v1 has packages/opencode, v2 deleted it for the split
#   packages/{cli,server,client,tui,...} layout. Runs on the HOST (a plain
#   call, not a command substitution -- a subshell would discard the
#   assignment) and is called before the buildah run body quotes ${OC_SRC_OUT}.
# Globals:
#   OPENCODE_API (string): generation selector
# Outputs:
#   Sets OC_SRC_OUT (string)
# ---------------------------------------------------------------------------
ocbin_source_layout() {
  case "${OPENCODE_API}" in
    v1) OC_SRC_OUT="packages/opencode/dist/opencode-linux-x64/bin/opencode" ;;
    v2) OC_SRC_OUT="packages/cli/dist/cli-linux-x64/bin/opencode" ;;
  esac
}

# ---------------------------------------------------------------------------
# ocbin_source_install_cmds() / ocbin_source_build_cmds()
#
# Description: emit the shell fragment for the current generation's install and
#   build steps. Split out of build_ocbin_source because they run INSIDE a
#   double-quoted buildah run body, so an inline case there would be re-expanded
#   by the host shell and silently lose its own generation test. These return
#   the fragment instead, and the case is evaluated on the host where
#   OPENCODE_API still means what it says.
#
# v1 install: --ignore-scripts plus an explicit fix-node-pty call, because the
#   install is told not to run lifecycle scripts.
#
# v2 install: no --ignore-scripts, so the root postinstall
#   (bun run --cwd packages/core fix-node-pty) runs the way it does upstream.
#   It only chmods node-pty's prebuilt spawn-helper and no-ops when hoisted.
#   --frozen-lockfile makes the workspace resolve from the tag's own bun.lock
#   instead of re-resolving, so a rebuild of the same hash is byte-stable.
#
# v2 build: packages/cli/script/build.ts is a single Bun.build + --compile of
#   src/index.ts into a self-contained executable. Three flags matter:
#     --single       build only the host platform/arch (linux-x64), so the
#                    result is one binary instead of twelve.
#     --skip-install do not let build.ts run its own
#                    `bun install --os=* --cpu=*` of every platform's
#                    @opentui/core and @opencode-ai/pty. The install above
#                    already put the host-platform packages in place:
#                    @opencode-ai/pty is a plain dependency of packages/cli,
#                    so it pulled @opencode-ai/pty-linux-x64-gnu, which is what
#                    resolveOpencodePty() embeds.
#     (no --skip-web-ui) the solidjs/vite build of packages/app runs and its
#                    brotli-compressed output is baked into the executable as
#                    the web UI asset archive.
#   Output lands in packages/cli/dist/cli-linux-x64/bin/opencode -- note the
#   directory is cli-linux-x64, not opencode-linux-x64 (build.ts rewrites the
#   target name before writing).
# Globals:
#   OPENCODE_API (string): generation selector
#   BUILD_JOBS (int): turbo concurrency (v1 only; v2 build.ts is single-pass)
# Outputs:
#   Prints a shell fragment
# ---------------------------------------------------------------------------
ocbin_source_install_cmds() {
  case "${OPENCODE_API}" in
    v1)
      printf '%s' "bun install --backend=copyfile --ignore-scripts --network-concurrency=1
    HUSKY=0 bun run --cwd packages/core fix-node-pty"
      ;;
    v2)
      printf '%s' "bun install --frozen-lockfile --network-concurrency=1"
      ;;
  esac
}

ocbin_source_build_cmds() {
  case "${OPENCODE_API}" in
    v1)
      printf '%s' "bun x turbo run build --filter=opencode --concurrency ${BUILD_JOBS} \\
      --env-mode=loose -- --single"
      ;;
    v2)
      printf '%s' "bun run --cwd packages/cli script/build.ts \\
      --single --skip-install --outdir=dist"
      ;;
  esac
}

# ---------------------------------------------------------------------------
# build_ocbin_binary()
#
# Description: layers the pinned upstream opencode release binary onto a scratch
#   rootfs, after VERIFYING it against a digest published by the upstream
#   registry. The registry differs per generation, but the property does not:
#   both paths pin a version and verify a digest computed by the publisher, so
#   a swapped or truncated download fails the build instead of becoming an image.
#
#   v1 -- GitHub Releases. The release for the tag carries
#   opencode-linux-x64.tar.gz with a sha256 `.digest`, checked with sha256sum.
#
#   v2 -- npm. A v2 tag never gets a GitHub Release: releases/tags/v2.x.y is a
#   404, and no workflow creates one (publish.yml pushes npm and one ghcr image;
#   release-github-action.yml only bumps github-v* tags for the legacy v1
#   action). The npm launcher opencode-ai does not track v2 either -- its latest
#   dist-tag is still 1.18.34. v2 ships as the per-platform package
#   @opencode/cli-linux-x64, whose registry manifest carries a sha512
#   dist.integrity for the tarball. Same guarantee, different authority.
# Globals:
#   OPENCODE_TAG (string): release tag whose binary is downloaded
#   LATEST_VERSION (string): version of that release (npm path)
#   OC_DEFAULT_VERSION (string): fallback version (npm path)
#   RESOLVED_HASH (string): tag hash; names the per-hash DL subdir
#   DL (string): host dir holding downloaded release tarballs
#   OC_BIN_IMG (string): image name committed when complete
# Outputs:
#   Commits ${OC_BIN_IMG} with /usr/local/bin/opencode
# ---------------------------------------------------------------------------
build_ocbin_binary() {
  local release_tag download_dir container
  release_tag="${OPENCODE_TAG}"
  download_dir="${DL}/${RESOLVED_HASH}"
  mkdir -p "${download_dir}"

  if [ ! -x "${download_dir}/opencode" ]; then
    case "${OPENCODE_API}" in
      v1) fetch_ocbin_v1 "${release_tag}" "${download_dir}" ;;
      v2) fetch_ocbin_v2 "${release_tag}" "${download_dir}" ;;
    esac
  fi
  chmod +x "${download_dir}/opencode"

  container=$(buildah from scratch)
  buildah copy "$container" "${download_dir}/opencode" /usr/local/bin/opencode
  buildah config --env OPENCODE_BINARY=1 "$container"
  buildah commit --rm "$container" "${OC_BIN_IMG}"
}

# ---------------------------------------------------------------------------
# fetch_ocbin_v1(<release_tag>, <download_dir>)
#
# Description: downloads the GitHub Release tarball for a v1 tag and verifies
#   it against the sha256 digest the release asset publishes.
# Globals:
#   DL (string): host dir the tarball is staged through
# Outputs:
#   Extracts <download_dir>/opencode
# ---------------------------------------------------------------------------
fetch_ocbin_v1() {
  local release_tag="$1" download_dir="$2" tarball asset_digest
  tarball="${download_dir}/opencode-linux-x64.tar.gz"

  info "==> Resolving pinned binary release digest (${release_tag})..."
  asset_digest=$(curl -fsSL "https://api.github.com/repos/anomalyco/opencode/releases/tags/${release_tag}" |
    jq -r '.assets[] | select(.name == "opencode-linux-x64.tar.gz") | .digest')
  if [ -z "${asset_digest}" ]; then
    error "No opencode-linux-x64.tar.gz digest published for ${release_tag}."
    info "  A v1 release must carry the asset; check the tag exists upstream."
    return 1
  fi
  ok " Digest locked: ${asset_digest}"

  curl -fL --retry 3 -o "${tarball}" \
    "https://github.com/anomalyco/opencode/releases/download/${release_tag}/opencode-linux-x64.tar.gz"
  echo "${asset_digest#sha256:}  ${tarball}" | sha256sum -c -
  tar -xzf "${tarball}" -C "${download_dir}"
  rm -f "${tarball}"
}

# ---------------------------------------------------------------------------
# fetch_ocbin_v2(<release_tag>, <download_dir>)
#
# Description: downloads the @opencode/cli-linux-x64 tarball for a v2 version
#   and verifies it against the sha512 dist.integrity the npm registry
#   publishes, then lifts the single bin/opencode out of it.
#
#   The package name is not a free choice -- publish.ts derives it from the
#   build target (@opencode/cli- + the linux-x64 target), so a package that
#   resolves for v2.0.22 is proof the release pipeline produced that version.
# Globals:
#   LATEST_VERSION, OC_DEFAULT_VERSION (string): version to fetch
# Outputs:
#   Extracts <download_dir>/opencode
# Returns:
#   Exits 1 if the version is unpublished, the integrity field is missing, or
#     the tarball does not verify
# ---------------------------------------------------------------------------
fetch_ocbin_v2() {
  local release_tag="$1" download_dir="$2"
  local pkg version manifest tarball tarball_url integrity

  pkg="@opencode/cli-linux-x64"
  version="${LATEST_VERSION:-$OC_DEFAULT_VERSION}"
  tarball="${download_dir}/${pkg##*/}-${version}.tgz"

  info "==> Resolving pinned binary integrity (${pkg}@${version})..."
  manifest=$(curl -fsSL "https://registry.npmjs.org/${pkg//\//%2f}/${version}" 2>/dev/null || true)
  if [ -z "${manifest}" ]; then
    error "npm has no published ${pkg}@${version}."
    info "  Upstream only publishes a v2 binary once the release job runs; check the tag exists."
    return 1
  fi

  integrity=$(printf '%s' "${manifest}" | jq -r '.dist.integrity // empty')
  tarball_url=$(printf '%s' "${manifest}" | jq -r '.dist.tarball // empty')
  if [ -z "${integrity}" ] || [ -z "${tarball_url}" ]; then
    error "No dist.integrity/dist.tarball in the ${pkg}@${version} manifest; refusing an unverified download."
    return 1
  fi
  ok " Integrity locked: ${integrity}"

  curl -fL --retry 3 -o "${tarball}" "${tarball_url}"
  # dist.integrity is "sha512-<base64>" but sha512sum prints hex, so convert.
  # od/tr rather than xxd: xxd is a vim package, not a base install, and this
  # script runs on whatever host does the build.
  printf '%s  %s\n' \
    "$(printf '%s' "${integrity#sha512-}" | base64 -d | od -An -v -tx1 | tr -d ' \n')" \
    "${tarball}" | sha512sum -c -
  # npm tarballs carry a "package/bin/" prefix. Naming the single member keeps
  # the 236-byte package.json out of the image, and stripping TWO components
  # lands it at <download_dir>/opencode, matching the v1 layout that
  # build_ocbin_binary copies into the image.
  tar -xzf "${tarball}" -C "${download_dir}" --strip-components=2 package/bin/opencode
  rm -f "${tarball}"
}

# ---------------------------------------------------------------------------
# build_pgassets()
#
# Description: installs the postgres 18 client, dev headers and pgvector
#   (built from source) but stages what the server image needs into
#   /pg-layer/... so compose can cherry-pick the payload
#   (usr/lib/postgresql, usr/share/postgresql, libpq*.so).
# Globals:
#   PGVER (string): pgvector version; drives the git checkout
#   BUILD_JOBS (int): parallelism for the pgvector make
#   CACHE (string): host cache dir; pgvector git checkout cached
#   PGA_IMG (string): image name committed when complete
# Outputs:
#   Commits ${PGA_IMG} with the /pg-layer payload staging tree
# ---------------------------------------------------------------------------
build_pgassets() {
  local container
  container=$(buildah from "${BASE_IMG}")
  buildah run --volume "${CACHE}:/mnt/host_cache" "$container" -- bash -ec "
    set -e
    apt-get update && apt-get install -y --no-install-recommends gnupg lsb-release
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | \
      gpg --dearmor -o /usr/share/keyrings/postgresql.gpg
    printf 'Types: deb\nURIs: https://apt.postgresql.org/pub/repos/apt\nSuites: %s-pgdg\nComponents: main\nSigned-By: /usr/share/keyrings/postgresql.gpg\n' \
      \"\$(lsb_release -cs)\" > /etc/apt/sources.list.d/pgdg.sources
    apt-get update && apt-get install -y --no-install-recommends \
      postgresql-server-dev-18 postgresql-client-18 libpq-dev git make gcc
    cd /tmp
    if [ ! -d /mnt/host_cache/pgvector_src/pgvector-${PGVER} ]; then
      git clone --branch v${PGVER} --depth 1 \
        https://github.com/pgvector/pgvector.git \
        /mnt/host_cache/pgvector_src/pgvector-${PGVER}
    fi
    rm -rf /tmp/pgvector-${PGVER}
    cp -r /mnt/host_cache/pgvector_src/pgvector-${PGVER}/. /tmp/pgvector-${PGVER}/
    cd /tmp/pgvector-${PGVER}
    make -j${BUILD_JOBS}
    make install
    cd /tmp && rm -rf /tmp/pgvector-${PGVER}
  "
  buildah run "$container" -- bash -ec "
    set -e
    mkdir -p /pg-layer/usr/lib/postgresql /pg-layer/usr/share/postgresql
    cp -a /usr/lib/postgresql/. /pg-layer/usr/lib/postgresql/
    cp -a /usr/share/postgresql/. /pg-layer/usr/share/postgresql/
    mkdir -p /pg-layer/usr/lib/x86_64-linux-gnu
    cp -a /usr/lib/x86_64-linux-gnu/libpq* /pg-layer/usr/lib/x86_64-linux-gnu/
  "
  buildah commit --rm "$container" "${PGA_IMG}"
}

# ---------------------------------------------------------------------------
# build_rusttools()
#
# Description: bootstraps rustup inside the container and `cargo install`s
#   lean-ctx into /usr/local/bin. The only layer meant to be rebuilt when
#   lean-ctx upstream moves.
# Globals:
#   BUILD_JOBS (int): CARGO_BUILD_JOBS + --jobs parallelism
#   CACHE (string): host cache dir; apt debs bound at /mnt/host_cache
#   APTDROP (string): apt snippet pinning debs to the host cache
#   RUST_IMG (string): image name committed when complete
# Outputs:
#   Commits ${RUST_IMG} with /usr/local/bin/lean-ctx
# ---------------------------------------------------------------------------
build_rusttools() {
  local container
  container=$(buildah from docker.io/library/debian:trixie-slim)
  buildah config --env DEBIAN_FRONTEND=noninteractive "$container"
  buildah config --env HOME=/root "$container"
  buildah run --volume "${CACHE}:/mnt/host_cache" "$container" -- bash -ec "
    set -e
    mkdir -p /mnt/host_cache/apt_cache/partial
    ${APTDROP}
    apt-get update && apt-get install -y --no-install-recommends \
      build-essential ca-certificates curl git pkg-config libssl-dev
    curl --proto '=https' --tlsv1.3 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
  "
  buildah config --env CARGO_BUILD_JOBS="${BUILD_JOBS}" "$container"
  buildah run "$container" -- bash -ec "
    set -e
    . \$HOME/.cargo/env
    cargo install lean-ctx --root /usr/local --jobs ${BUILD_JOBS}
  "
  buildah commit --rm "$container" "${RUST_IMG}"
}

# ---------------------------------------------------------------------------
# build_gobin()
#
# Description: the standalone CLI tools the image carries as single binaries.
#   yq + gomplate are Go, installed from module-proxy into /usr/local/bin via
#   the official golang image; the go module + build caches live on the host
#   bind-mount so repeat runs are incremental. The gomplate major must track
#   the `docker.io/hairyhenderson/gomplate` image the `just template` recipe
#   renders with: /v5 is current, and /v4 silently pins v4.3.3. It is pinned
#   exactly (not @latest) and stamped via -ldflags, because a go-installed
#   binary otherwise reports "gomplate version 0.0.0" -- the goreleaser
#   ldflags are not applied by `go install`, and the agent needs to be able to
#   tell which gomplate it is validating with. The -ldflags value is therefore
#   nested inside the `bash -ec "..."` argument, so its quotes MUST stay
#   escaped (\"): the host shell strips unescaped ones, which silently turns
#   the value into a second, @version-less package argument and fails the
#   build with "go: go.mod file not found" rather than at the flag. `grep`ping
#   the reported version back is what catches a stamp that silently dropped.
#   hadolint is Haskell, not Go (its repo is a .cabal project, so `go install`
#   cannot work), so it comes from the sha256-VERIFIED GitHub release,
#   host-side, like the ocbin binary.
# Globals:
#   CACHE (string): host cache dir; go module/build caches at /mnt/host_cache/go
#   DL (string): host dir holding the hadolint release download
#   HADOLINT_VERSION (string): hadolint release tag, default v2.15.1
#   GOMPLATE_VERSION (string): gomplate release tag, default v5.2.0
#   AGE_VERSION (string): age module tag, default v1.3.2. One pin covers age,
#     age-keygen and age-plugin-batchpass -- all three main packages live in
#     the same filippo.io/age module
#   GOBIN_IMG (string): image name committed when complete
# Outputs:
#   Commits ${GOBIN_IMG} with
#     /usr/local/bin/{yq,gomplate,hadolint,age,age-keygen,age-plugin-batchpass}
# ---------------------------------------------------------------------------
build_gobin() {
  local container hadolint_asset hadolint_dir
  hadolint_asset="hadolint-linux-x86_64"
  hadolint_dir="${DL}/hadolint-${HADOLINT_VERSION}"
  mkdir -p "${hadolint_dir}"

  if [ ! -x "${hadolint_dir}/hadolint" ]; then
    info "==> Fetching ${hadolint_asset} ${HADOLINT_VERSION} (sha256 verified)..."
    curl -fL --retry 3 -o "${hadolint_dir}/${hadolint_asset}" \
      "https://github.com/hadolint/hadolint/releases/download/${HADOLINT_VERSION}/${hadolint_asset}"
    curl -fL --retry 3 -o "${hadolint_dir}/checksums.sha256" \
      "https://github.com/hadolint/hadolint/releases/download/${HADOLINT_VERSION}/checksums.sha256"
    # the release publishes one checksums file for every platform asset, so
    # verify just the line for ours (sha256sum -c on the whole file fails on
    # the macos/windows entries we did not download).
    (cd "${hadolint_dir}" &&
      grep -F " *${hadolint_asset}" checksums.sha256 | sha256sum -c -)
    cp "${hadolint_dir}/${hadolint_asset}" "${hadolint_dir}/hadolint"
    chmod +x "${hadolint_dir}/hadolint"
  fi

  container=$(buildah from docker.io/library/golang:latest)
  buildah config --env HOME=/root "$container"
  buildah config --env GOPATH=/mnt/host_cache/go "$container"
  buildah config --env GOMODCACHE=/mnt/host_cache/go/pkg/mod "$container"
  buildah config --env GOCACHE=/mnt/host_cache/go/cache "$container"
  buildah run --volume "${CACHE}:/mnt/host_cache" "$container" -- bash -ec "
    set -e
    export GOBIN=/usr/local/bin
    go install github.com/mikefarah/yq/v4@latest
    go install -ldflags \"-X github.com/hairyhenderson/gomplate/v5/version.Version=${GOMPLATE_VERSION}\" \
      github.com/hairyhenderson/gomplate/v5/cmd/gomplate@${GOMPLATE_VERSION}
    yq --version
    gomplate --version | grep -q \"${GOMPLATE_VERSION}\"
    # age + age-keygen + age-plugin-batchpass, all from the one pinned module.
    # The --version greps need no ldflags here because 'go install pkg@ver'
    # stamps debug.ReadBuildInfo().Main.Version, which is exactly what both
    # main packages print (unlike gomplate, whose stamp is a goreleaser one).
    # (No backticks in this comment: it lives inside a double-quoted argument,
    # so any would be command substitution in the HOST shell, not a comment.)
    go install filippo.io/age/cmd/age@${AGE_VERSION}
    go install filippo.io/age/cmd/age-keygen@${AGE_VERSION}
    go install filippo.io/age/cmd/age-plugin-batchpass@${AGE_VERSION}
    age --version | grep -q \"${AGE_VERSION}\"
    age-keygen --version | grep -q \"${AGE_VERSION}\"
    # The plugin is resolved BY NAME ON PATH (age searches PATH for
    # age-plugin-<name>), which no --version can prove, so the exec bit and
    # PATH-reachability are asserted directly and then exercised end to end.
    # Without this roundtrip a plugin that installed fine but is unreachable
    # would pass every check above and fail only in production. Work factor 1
    # keeps scrypt instant at build time.
    test -x /usr/local/bin/age-plugin-batchpass
    printf probe | AGE_PASSPHRASE=testpass AGE_PASSPHRASE_WORK_FACTOR=1 \
      age -e -j batchpass > /tmp/age-probe.age
    AGE_PASSPHRASE=testpass age -d -j batchpass /tmp/age-probe.age | grep -q probe
    rm -f /tmp/age-probe.age
  "
  buildah copy "$container" "${hadolint_dir}/hadolint" /usr/local/bin/hadolint
  buildah run "$container" -- chmod +x /usr/local/bin/hadolint
  buildah commit --rm "$container" "${GOBIN_IMG}"
}

# ---------------------------------------------------------------------------
# build_uvbin()
#
# Description: strips uv and uvx out of the official astral-sh image and
#   re-layers just those two binaries onto a scratch rootfs so merge_payload
#   can place them arbitrarily.
# Globals:
#   UVBIN_IMG (string): image name committed when complete
# Outputs:
#   Commits ${UVBIN_IMG} containing /uv and /uvx at the rootfs root
# ---------------------------------------------------------------------------
build_uvbin() {
  local source_container container
  source_container=$(buildah from ghcr.io/astral-sh/uv:latest)
  container=$(buildah from scratch)
  buildah copy --from="$source_container" "$container" /uv /uvx /
  buildah rm "$source_container"
  buildah commit --rm "$container" "${UVBIN_IMG}"
}

# ---------------------------------------------------------------------------
# build_mcp()
#
# Description: pre-installs the MCP/LSP tool payload into
#   /home/opencode/.local (uv tools + global npm packages) as ROOT, then
#   chowns it to the image's own `opencode` user; the whole .local tree is
#   later merged into composed servers, which chown /home/opencode again.
#   Includes: semble[mcp], code-index-mcp, repomix, bash-language-server,
#   yaml-language-server, dockerfile-language-server, @ast-grep/cli, pyright,
#   check-jsonschema, plus python-lsp-server installed INTO the pydex python
#   (not a uv tool -- each uv tool below lands on the image's one Python via
#   UV_PYTHON; pylsp must be that same interpreter, because jedi resolves
#   against get_default_environment().executable, the interpreter RUNNING
#   pylsp). Declares the uv tool/npm prefix env the tools need.
#   Builds FROM pydex with UV_PYTHON pinned, so every uv tool here lands on the
#   image's one Python instead of a uv-managed download of its own.
# Globals:
#   PYDEX_IMG, UVBIN_IMG (string): base images (uv is not in pydex)
#   MCP_IMG (string): image name committed when complete
# Outputs:
#   Commits ${MCP_IMG} with the populated /home/opencode/.local plus a staged
#   /mcp-layer/opt (pylsp's interpreter trees) that compose_server contents-
#   merges over the pydex /opt the finals already carry.
# ---------------------------------------------------------------------------
build_mcp() {
  local uv_container container
  container=$(buildah from "${PYDEX_IMG}")
  uv_container=$(buildah from "${UVBIN_IMG}")
  buildah copy --from="$uv_container" "$container" /uv /uvx /bin/
  buildah rm "$uv_container"
  buildah config --env HOME=/home/opencode "$container"
  buildah config --env UV_TOOL_DIR=/home/opencode/.local/share/uv/tools "$container"
  buildah config --env UV_TOOL_BIN_DIR=/home/opencode/.local/bin "$container"
  # uv's python-preference defaults to "managed", i.e. it downloads and uses
  # its own CPython and ignores both pydex and the system one. That would leave
  # the MCP/LSP tools on a floating interpreter that nothing in the build
  # controls. UV_PYTHON pins every uv tool below to pydex ${PYVER}.
  buildah config --env UV_PYTHON="/opt/python-${PYVER}/bin/python3" "$container"
  buildah config --env NPM_CONFIG_PREFIX=/home/opencode/.local "$container"
  # Root, not --user opencode, for the same two reasons build_pydex points its
  # own HOME at root's home:
  #   * the parent layer is shared through the registry and is built by root
  #     runs, so $HOME can carry root-owned state a non-root uid cannot write
  #     past -- that is exactly how a cached pydex killed this layer;
  #   * a bind mount is not userns-rewritten, so the host cache appears inside
  #     the container as uid 0 and only root can write it. Nothing in this body
  #     needs it (uv and npm both cache under $HOME), so it is not mounted.
  # The chown is by NAME, so it follows the uid the image's passwd gives
  # `opencode` rather than the baking host's HOST_UID -- the two differ per
  # host (systemd-homed bakes 60139, a normal account bakes 1000) and layers
  # are pushed to a registry both kinds of host build from.
  buildah run "$container" -- bash -ec '
    set -e
    uv tool install --with mcp "semble[mcp]"
    uv tool install "code-index-mcp"
    # pylsp is the exception to the uv tool rule: it goes into the pydex
    # python ITSELF, not a tool env. jedi, its import engine, resolves against
    # get_default_environment().executable -- the interpreter RUNNING pylsp,
    # not whatever PATH first names -- so a tool-env pylsp reads a venv whose
    # site-packages has neither jinja2 nor yaml, and no PYTHONPATH fix helps.
    # uv, not pip, for the same reason build_ansible uses it: UV_PYTHON pins
    # the target and that interpreter carries no PEP 668 marker. The assertion
    # proves the mechanism rather than trusting PATH, and no tool-env copy is
    # left behind to uninstall: this run never creates one.
    uv pip install --system --python "$UV_PYTHON" "python-lsp-server"
    # The which() check runs first: while a tool env is the regression, /opt
    # carries no jedi yet, so importing jedi up front would report
    # ModuleNotFoundError instead of the actual wrong location. It has to be
    # PATH-scoped to the pydex bin dir: the build run inside this layer does
    # carry the runtime PATH -- compose_server stops /opt/python-${PYVER}/bin
    # first on the final image (os.path.dirname(sys.executable), since the
    # assertion runs through UV_PYTHON), so a bare shutil.which() here scans
    # pydex default PATH and finds nothing even on a correct install.
    "$UV_PYTHON" -c "import os, shutil, sys, jedi; p=shutil.which(\"pylsp\", path=os.path.dirname(sys.executable)); assert p and p.startswith(\"/opt/python-\"), (\"pylsp on %r\" % p); e=jedi.api.environment.get_default_environment(); assert e.executable.startswith(\"/opt/python-\"), (\"jedi env %r\" % e.executable); print(\"pylsp OK\", p, e.executable)"
    npm install -g \
      --registry=https://registry.npmjs.org \
      --network-concurrency=8 \
      --fetch-retry-maxtimeout=300000 \
      --fetch-timeout=300000 \
      repomix bash-language-server \
      yaml-language-server dockerfile-language-server-nodejs \
      @ast-grep/cli pyright
    uv tool install "check-jsonschema"
    rm -rf /home/opencode/.npm /home/opencode/.cache
    chown -R opencode: /home/opencode/.local
  '
  buildah run "$container" -- bash -ec "
    set -e
    mkdir -p /mcp-layer/opt/python-${PYVER}/lib/python${PYVER%.*}
    # pylsp is installed into the pydex python (see the install run), so its
    # site-packages and bin travel with the payload the same way the ansible
    # layer's do. Left root-owned to match the /opt pydex already puts in the
    # finals; the chown above covers /home/opencode only.
    cp -a /opt/python-${PYVER}/lib/python${PYVER%.*}/site-packages /mcp-layer/opt/python-${PYVER}/lib/python${PYVER%.*}/
    cp -a /opt/python-${PYVER}/bin /mcp-layer/opt/python-${PYVER}/
  "
  buildah commit --rm "$container" "${MCP_IMG}"
}

# ---------------------------------------------------------------------------
# build_devtools()
#
# Description: the agent's validation/debug toolchain as its own layer, so it
#   can be added to or changed without invalidating the base -> pydex chain.
#   Go and Rust are NOT here: they arrive as layers already (the gobin layer
#   for go, rustup in build_rusttools for lean-ctx).
#   apt installs straight into the rootfs and the layer is committed as-is;
#   compose_server merges /usr, /etc and /var straight out of the image. This
#   layer used to stage a copy into /dev-layer/{usr,etc,var} first, which was
#   pure duplication -- the whole base filesystem ended up in the layer twice
#   (once at /usr, once at /dev-layer/usr) and compose merged only the
#   duplicate back out. It cost ~1GB per layer and bought no isolation, since
#   /dev-layer was not shipped, just a copy of paths that were already there.
#   Contrast build_pgassets, which stages only targeted paths (/pg-layer/...)
#   because it installs those tools under a dedicated prefix and the rest of
#   its /usr is base's, unchanged.
# Globals:
#   CACHE (string): host cache dir; apt debs bound at /mnt/host_cache
#   APTDROP (string): apt snippet pinning debs to the host cache
#   DEVTOOLS_IMG (string): image name committed when complete
# Outputs:
#   Commits ${DEVTOOLS_IMG} with the toolchain installed in the rootfs
# ---------------------------------------------------------------------------
build_devtools() {
  local container
  container=$(buildah from "${BASE_IMG}")
  buildah config --env DEBIAN_FRONTEND=noninteractive "$container"
  # ansible/ansible-core/ansible-lint are deliberately NOT here. They come from
  # the uv-managed environment in build_ansible so they run against pydex
  # ${PYVER} instead of Debian's system python3 -- the point of moving ansible
  # off the apt list. No python3-* libraries are installed here either: apt
  # wheels are built for Debian's python3, so they are useless to a 3.14 venv.
  # yamllint is a standalone binary and needs neither.
  # dnscrypt-proxy is here on purpose -- the agent validates the config it
  # writes with dnscrypt-proxy --check. Know what that buys: on 2.1.8 (what
  # trixie ships, above the 2.0.46 floor) --check and --list-all both exit 0
  # on a STAMP with a single mistyped base64 character, byte-identical output
  # and all. Only structural damage trips it, rc=255 with [FATAL] Stamp error.
  # So --check is not a content check: review stamps in git, and use this for
  # the shape of the file.
  buildah run --volume "${CACHE}:/mnt/host_cache" "$container" -- bash -ec "
    set -e
    mkdir -p /mnt/host_cache/apt_cache/partial
    ${APTDROP}
    apt-get update && apt-get install -y --no-install-recommends \
      just \
      yamllint \
      dnscrypt-proxy \
      iproute2 iputils-ping bind9-dnsutils netcat-openbsd traceroute \
      procps psmisc lsof file tree strace \
      skopeo gnupg unzip zstd rsync sqlite3 \
      cpio initramfs-tools-core cryptsetup-bin
  "
  buildah commit --rm "$container" "${DEVTOOLS_IMG}"
}

# ---------------------------------------------------------------------------
# build_ansible()
#
# Description: the pinned uv-managed Python/Ansible validation environment.
#   Builds on PYDEX_IMG so ansible runs against the same CPython ${PYVER} the
#   agent's other tooling uses, not Debian's system python3 -- the point of
#   moving ansible off the apt list in build_devtools.
#   Installs ansible-core INTO the pydex python (uv pip install --system, so
#   the interpreter `python3` resolves to can import it) and ansible-lint as a
#   uv tool env (it needs black, ruamel.yaml and the rest of that closure),
#   then bakes the Galaxy collections (ansible.posix, community.general) into
#   the payload so validation works offline at runtime. Both are named
#   directly rather than pulled in as a dependency of the community `ansible`
#   package, which carries only the ansible-community stub.
#   Staged at /ansible-layer so compose_server can cherry-pick it the same way
#   it does for the mcp layer: /ansible-layer/home/opencode for the tool env and
#   the collections, /ansible-layer/opt for ansible-core's site-packages and
#   the CLI scripts.
# Args:
#   None
# Globals:
#   PYDEX_IMG, UVBIN_IMG (string): base images (uv is not in pydex)
#   ANSIBLE_CORE_VERSION, ANSIBLE_LINT_VERSION (string): pinned PyPI versions
#   ANSIBLE_POSIX_VERSION, ANSIBLE_COMMUNITY_GENERAL_VERSION (string): pinned
#     Galaxy collection versions
#   CACHE (string): host build cache, used to keep the Galaxy tarballs
# Outputs:
#   Commits ${ANSIBLE_IMG} with /ansible-layer staged
# ---------------------------------------------------------------------------
build_ansible() {
  local container uv_container
  container=$(buildah from "${PYDEX_IMG}")
  uv_container=$(buildah from "${UVBIN_IMG}")
  buildah copy --from="$uv_container" "$container" /uv /uvx /bin/
  buildah rm "$uv_container"
  buildah config --env HOME=/home/opencode "$container"
  buildah config --env UV_TOOL_DIR=/home/opencode/.local/share/uv/tools "$container"
  buildah config --env UV_TOOL_BIN_DIR=/home/opencode/.local/bin "$container"
  buildah config --env UV_PYTHON="/opt/python-${PYVER}/bin/python3" "$container"
  # Both runs below are root, for the same two reasons as build_mcp's: a bind
  # mount is not userns-rewritten, so the host cache (owned by the invoking
  # uid) appears inside the container as uid 0 and only root can write it; and
  # the parent layer is shared through the registry and built by root runs, so
  # $HOME can carry root-owned state a non-root uid cannot write past. Galaxy
  # is the one step that reaches a non-PyPI index and the one step that writes
  # the host cache, so it keeps its own run and the volume stays on that run
  # only -- the install run does not mount it.
  # The payload is chowned to the image's own `opencode` user (by NAME, so it
  # follows the image's uid rather than the baking host's HOST_UID) before it
  # is staged, so the layer is uid-owned on its own; compose_server chowns
  # /home/opencode again after the merge, so neither copy depends on the other.
  # ANSIBLE_GALAXY_CACHE_DIR keeps the tarballs on the host cache (the supported
  # knob; `collection install` has no --download-path, that flag is on
  # `download`). build_base sets no PATH, so the bin dir beside the pydex
  # python is not on it either -- call ansible-galaxy by absolute path rather
  # than adding a PATH.
  # The version pins come in as $1/$2/$3 rather than being interpolated, so
  # the install run's body can stay single-quoted (like build_mcp) and keep its
  # comments free of quoting games.
  buildah run "$container" -- bash -ec '
    set -e
    # ansible-core goes into the pydex python ITSELF, not into a uv tool env.
    # A tool env is invisible to the interpreter that `python3` resolves to, so
    # `python3 -c "import ansible"`, the ad-hoc interpreter work and the LSP all
    # come up empty against it -- and ansible-core drags in Jinja2 and PyYAML, so
    # those are empty too. uv, not pip, because UV_PYTHON pins the target and
    # uv does not re-resolve an interpreter the way a bare `pip` can; --system
    # is what lets it write to a non-venv interpreter, and that interpreter
    # carries no PEP 668 marker, so nothing needs --break-system-packages.
    # Installing here rather than alongside the tool env is also the cheaper
    # half of the choice: the ten CLIs land in the bin dir beside the pydex
    # python, which is first on PATH, so there is no second copy to link into
    # .local/bin.
    uv pip install --system --python "$UV_PYTHON" \
      "ansible-core==$1"
    # ansible-lint keeps its own tool env: it needs black, ruamel.yaml and the
    # rest of its closure, and `uv tool install` is the only thing here that
    # resolves that. It also carries its own ansible-core, which is the second
    # and last copy -- the version assertion below has to cover it.
    uv tool install \
      "ansible-lint==$2"
    # UV_PYTHON pins the lint env to the pydex interpreter. Assert it rather
    # than trust it: a uv or venv change that let a managed interpreter in
    # would otherwise surface much later as the agent linting against a python
    # other than $3, with nothing in the image to explain it.
    # chr(46) is a dot, so the -c code carries no quotes of its own and this
    # body can stay single-quoted.
    got=$("$UV_TOOL_DIR/ansible-lint/bin/python" -c "import sys; print(*sys.version_info[:2], sep=chr(46))")
    [ "$got" = "$3" ] || { echo "tool venv ansible-lint is on python $got, not $3" >&2; exit 1; }
    # The agent imports ansible from the PATH python3, so prove the image can
    # do that before it ships -- a wrong install target would otherwise surface
    # as an unresolved import in the agent, with nothing in the build to explain
    # it. The decoy directory is the point. Playbook checkouts are full of
    # `ansible/` dirs, cwd is first on sys.path, and a directory with no
    # __init__.py is a valid NAMESPACE package: a bare `import ansible` against
    # one of those exits 0 and prints a __path__, so a test that only imported
    # ansible would pass against a tree with nothing installed. Importing
    # ansible.parsing.splitter is what gives it teeth -- no playbook layout has
    # that submodule -- and the sibling jinja2/yaml imports fail the same way.
    # $UV_PYTHON is the interpreter PATH resolves to at runtime; the -c code
    # takes its argument from argv so this body needs no quoting.
    mkdir -p /tmp/ansible-import-check/ansible/tasks
    cd /tmp/ansible-import-check
    "$UV_PYTHON" -c "import sys, ansible, jinja2, yaml; from ansible.parsing.splitter import split_args; print(ansible.__version__, jinja2.__version__, yaml.__version__, split_args(sys.argv[1]))" "a b  c"
    cd /
    rm -rf /home/opencode/.cache
  ' buildah-ansible "${ANSIBLE_CORE_VERSION}" "${ANSIBLE_LINT_VERSION}" "${PYVER%.*}"
  buildah run --volume "${CACHE}:/mnt/host_cache" "$container" -- bash -ec "
    set -e
    export ANSIBLE_GALAXY_CACHE_DIR=/mnt/host_cache/ansible_galaxy
    mkdir -p \"\$ANSIBLE_GALAXY_CACHE_DIR\"
    # -p is --collections-path here. ANSIBLE_COLLECTIONS_PATH is set in
    # compose_server so the runtime resolves this same path. The binary sits
    # beside the pydex python, not in .local/bin -- see the install run.
    /opt/python-${PYVER}/bin/ansible-galaxy collection install \
      -p /home/opencode/.ansible/collections \
      'ansible.posix:${ANSIBLE_POSIX_VERSION}' \
      'community.general:${ANSIBLE_COMMUNITY_GENERAL_VERSION}'
  "
  buildah run "$container" -- bash -ec "
    set -e
    mkdir -p /ansible-layer/home/opencode
    # ansible-core is installed into the pydex python, so its two writable trees
    # have to travel with the payload: site-packages for the imports, bin for
    # the ten CLI scripts. The finals already carry an identical /opt from
    # pydex, so compose_server merges this over the top rather than replacing
    # it -- staging the whole interpreter instead would triple the layer.
    # Left root-owned on purpose, matching the /opt pydex already put there; the
    # chown below is for the /home/opencode payload only.
    mkdir -p /ansible-layer/opt/python-${PYVER}/lib/python${PYVER%.*}
    cp -a /opt/python-${PYVER}/lib/python${PYVER%.*}/site-packages /ansible-layer/opt/python-${PYVER}/lib/python${PYVER%.*}/
    cp -a /opt/python-${PYVER}/bin /ansible-layer/opt/python-${PYVER}/
    # cp -a preserves ownership, so the staged payload is only uid-owned if it
    # is chowned first -- including .ansible, which the root Galaxy run above
    # created after the install run already finished.
    chown -R opencode: /home/opencode/.local /home/opencode/.ansible
    cp -a /home/opencode/.local /ansible-layer/home/opencode/
    cp -a /home/opencode/.ansible /ansible-layer/home/opencode/
  "
  buildah commit --rm "$container" "${ANSIBLE_IMG}"
}

# ---------------------------------------------------------------------------
# merge_payload(<container>, <layer_image>, <source_rootfs_path>, <target_rootfs_path>)
#
# Description: layers a subtree from a committed layer image into a working
#   container using cp -a semantics, preserving ownership/permissions.
#   Both rootfs trees are buildah-mounted to the host, the payload is copied
#   root-first (a trailing '/' on <target_rootfs_path> means "into that dir").
#   A trailing "/." on <source_rootfs_path> requests CONTENTS-merge into an
#   existing target directory (cp -a of a <dir>/ onto an existing <dir>/
#   nests a subdirectory instead of merging the entries).
# Args:
#   $1  container (string): working container to receive the files
#   $2  layer_image (string): image the payload comes from
#   $3  source_rootfs_path (string): path inside <layer_image> rootfs
#   $4  target_rootfs_path (string): destination path inside <container> rootfs
# Outputs:
#   None directly; the <container> filesystem is modified and the temporary
#   source container is removed
# ---------------------------------------------------------------------------
merge_payload() {
  local container="$1" layer_image="$2" source_rootfs_path="$3" target_rootfs_path="$4"
  local source_container source_rootfs target_rootfs
  source_container=$(buildah from "$layer_image")
  source_rootfs=$(buildah mount "$source_container")
  target_rootfs=$(buildah mount "$container")
  mkdir -p "$(dirname "${target_rootfs}${target_rootfs_path}")"
  cp -a "${source_rootfs}${source_rootfs_path}" "${target_rootfs}${target_rootfs_path}"
  buildah umount "$container"
  buildah umount "$source_container"
  buildah rm "$source_container"
}

# ---------------------------------------------------------------------------
# compose_server(<stack>, <src>, <tail>)
#
# Description: assembles the opencode-server image by picking layers per
#   the variant. full picks pydex (python PATH prefix), pgassets, rusttools;
#   basic starts from base. Both merge ocbin, uvbin, gobin, mcp and devtools,
#   bake the opencode.json (lean_ctx only for full), normalise /home/opencode
#   ownership (chown HOST_UID:0, then chmod g=u), and set user/workdir/
#   entrypoint before committing. tail controls the local tag: empty ->
#   latest + <version>,
#   otherwise a distinct <tail> + <tail>-<version>.
# Args:
#   $1  stack (string): "full" or "basic"
#   $2  src (string): "source" or "binary"
#   $3  tail (string): "" (default variant) or a suffix like "basic",
#       "full-binary", "basic-binary"
# Globals:
#   PYVER (string): /opt/python-<PYVER> PATH prefix for full stacks
#   SERVER_IMG (string): namespace of the committed image
#   LATEST_VERSION (string): version tag suffix
#   STAGE (string): scratch dir holding the stripped -basic config
# Outputs:
#   Commits ${SERVER_IMG}:latest (or :<tail>) + version tag; prints ok
# ---------------------------------------------------------------------------
compose_server() {
  local stack="$1" src="$2" tail="$3" container ocbin_image python_path_prefix config_source
  config_source="${REPO_ROOT}/build/opencode/config/${OPENCODE_API:-v1}/opencode.jsonc"
  if [ ! -f "${config_source}" ]; then
    error "No opencode config for API generation '${OPENCODE_API:-v1}': ${config_source}"
    exit 1
  fi
  # Both stacks build FROM pydex now, so there is exactly one Python in the
  # image and it is pydex ${PYVER}. Debian's python3 still ships in the base
  # layer (build_pydex needs it to bootstrap the sigstore venv) but nothing
  # at runtime resolves to it: python_path_prefix puts /opt/python-${PYVER}/bin
  # ahead of /usr/bin, and /usr/local/bin/python3 is a symlink to the same.
  container=$(buildah from "${PYDEX_IMG}")
  python_path_prefix="/opt/python-${PYVER}/bin:"
  ocbin_image=$(ocbin_for "$src")

  merge_payload "$container" "$ocbin_image" /usr/local/bin/opencode /usr/local/bin/opencode
  merge_payload "$container" "${UVBIN_IMG}" /uv /bin/uv
  merge_payload "$container" "${UVBIN_IMG}" /uvx /bin/uvx
  merge_payload "$container" "${GOBIN_IMG}" /usr/local/bin/yq /usr/local/bin/yq
  merge_payload "$container" "${GOBIN_IMG}" /usr/local/bin/gomplate /usr/local/bin/gomplate
  merge_payload "$container" "${GOBIN_IMG}" /usr/local/bin/hadolint /usr/local/bin/hadolint
  merge_payload "$container" "${GOBIN_IMG}" /usr/local/bin/age /usr/local/bin/age
  merge_payload "$container" "${GOBIN_IMG}" /usr/local/bin/age-keygen /usr/local/bin/age-keygen
  # The plugin binary is NOT optional to the pair: age resolves it by name on
  # PATH at call time, so an image carrying only `age` would fail every
  # `age -j batchpass` (and every AGE_PASSPHRASE= script) with "plugin not
  # found" rather than anything a version check could catch.
  merge_payload "$container" "${GOBIN_IMG}" /usr/local/bin/age-plugin-batchpass /usr/local/bin/age-plugin-batchpass
  merge_payload "$container" "${MCP_IMG}" /home/opencode/.local /home/opencode/
  # pylsp's interpreter trees, contents-merged over the identical /opt pydex
  # already put here -- what makes jedi's default environment the pydex python
  # for BOTH stacks (basic merges mcp too, just not pgassets/rusttools).
  merge_payload "$container" "${MCP_IMG}" /mcp-layer/opt/. /opt
  # ansible payload, staged the same way as the mcp layer above. Both stacks
  # carry pydex now, so these venvs resolve and this is not full-only. Keeping
  # it shared preserves what basic had when ansible came from the devtools
  # apt list.
  merge_payload "$container" "${ANSIBLE_IMG}" /ansible-layer/home/opencode/.local /home/opencode/
  merge_payload "$container" "${ANSIBLE_IMG}" /ansible-layer/home/opencode/.ansible /home/opencode/
  # ansible-core's own trees, over the identical /opt pydex already put here.
  # Contents-merge for the same reason the devtools merges use "/.".
  merge_payload "$container" "${ANSIBLE_IMG}" /ansible-layer/opt/. /opt
  # devtools: apt installs into the layer's own rootfs, so these merge straight
  # from the image. The "/." contents-merge spelling is still required -- the
  # target /usr,/etc,/var all exist, and plain cp -a of a <dir>/ onto an
  # existing <dir>/ would nest usr/ inside usr/.
  merge_payload "$container" "${DEVTOOLS_IMG}" /usr/. /usr/
  merge_payload "$container" "${DEVTOOLS_IMG}" /etc/. /etc/
  merge_payload "$container" "${DEVTOOLS_IMG}" /var/. /var/
  if [ "${stack}" = full ]; then
    merge_payload "$container" "${PGA_IMG}" /pg-layer/usr/lib/postgresql /usr/lib/postgresql
    merge_payload "$container" "${PGA_IMG}" /pg-layer/usr/share/postgresql /usr/share/postgresql
    merge_payload "$container" "${PGA_IMG}" /pg-layer/usr/lib/x86_64-linux-gnu/. /usr/lib/x86_64-linux-gnu/
    merge_payload "$container" "${RUST_IMG}" /usr/local/bin/lean-ctx /usr/local/bin/lean-ctx
  fi

  buildah config --env HOME=/home/opencode "$container"
  buildah config --env NPM_CONFIG_PREFIX=/home/opencode/.local "$container"
  buildah config --env UV_TOOL_DIR=/home/opencode/.local/share/uv/tools "$container"
  buildah config --env UV_TOOL_BIN_DIR=/home/opencode/.local/bin "$container"
  # /usr/sbin is in the list because dnscrypt-proxy lives there and the agent
  # reaches it by name; the rest is Debian's default order, so nothing shadows
  # differently than it would on a stock box.
  buildah config --env PATH="${python_path_prefix}/home/opencode/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" "$container"
  # baked in the ansible layer, but named explicitly so a playbook run does not
  # depend on $HOME/.ansible defaulting the way the image user expects
  buildah config --env ANSIBLE_COLLECTIONS_PATH=/home/opencode/.ansible/collections "$container"
  buildah config --env ANSIBLE_HOME=/home/opencode/.ansible "$container"

  # the api config is the full-stack config; basic drops the lean_ctx entry.
  # v1 keeps it at mcp.lean_ctx, v2's native shape nests it at
  # mcp.servers.lean_ctx -- delete both so the basic stack cannot silently
  # start shipping lean_ctx when the v2 config is rewritten in its own shape.
  if [ "${stack}" = full ]; then
    buildah copy "$container" "${config_source}" /home/opencode/.config/opencode/opencode.json
  else
    jq 'del(.mcp.lean_ctx) | (if .mcp.servers then del(.mcp.servers.lean_ctx) else . end)' \
      "${config_source}" >"${STAGE}/opencode-basic.json"
    buildah copy "$container" "${STAGE}/opencode-basic.json" /home/opencode/.config/opencode/opencode.json
  fi
  buildah run "$container" -- bash -ec "
    mkdir -p /home/opencode/.local/share/opencode /home/opencode/.local/state/opencode \
      /home/opencode/.cache/opencode /home/opencode/.config/opencode /home/opencode/.npm
    chown -R ${HOST_UID}:0 /home/opencode
    chmod -R g=u /home/opencode
    # uid-agnostic runtime state: the fortress may run the container with
    # --userns keep-id + --user <invoking-host-uid>, which differs from the
    # bake-time HOST_UID on other hosts (e.g. 60139 on a systemd-homed box).
    # Traverse/exec for every identity across home, plus world-write on the
    # mutable XDG/workspace dirs so any identity can create state; binary
    # execute bits under .local are preserved (X only adds x to dirs).
    chmod -R o+X /home/opencode
    chmod -R o+rwX /home/opencode/.local/share/opencode /home/opencode/.local/state/opencode \
      /home/opencode/.cache/opencode /home/opencode/.config/opencode /home/opencode/workspace \
      /home/opencode/.npm
    # ...and the XDG roots themselves must be writable, not just their
    # children: .local/.config/.cache land root-owned from the layer merges
    # and MCP servers (lean-ctx among them) mkdir their OWN state dir under
    # .local/share on first run, which is EACCES without this.
    chmod o+rwx /home/opencode/.local /home/opencode/.local/share \
      /home/opencode/.config /home/opencode/.cache
  "
  buildah config --user opencode "$container"
  buildah config --workingdir /home/opencode/workspace "$container"
  buildah config --entrypoint '["opencode"]' "$container"

  if [ -z "${tail}" ]; then
    buildah commit --rm "$container" "${SERVER_IMG}:latest"
    buildah tag "${SERVER_IMG}:latest" "${SERVER_IMG}:${LATEST_VERSION}"
  else
    buildah commit --rm "$container" "${SERVER_IMG}:${tail}"
    buildah tag "${SERVER_IMG}:${tail}" "${SERVER_IMG}:${tail}-${LATEST_VERSION}"
  fi
  ok " Server image ready: ${SERVER_IMG}:${tail:-latest}"
}

# ---------------------------------------------------------------------------
# compose_tui(<src>, <tail>)
#
# Description: assembles the slim attach-only opencode-tui image: tui-base +
#   the ocbin binary, xdg state dirs, and opencode as entrypoint.
#   The state-dir run below keeps --user opencode, unlike the payload installs
#   in build_mcp/build_ansible: build_tui_base creates and chowns those dirs
#   itself, so the mkdirs are no-ops and only the o+rwX widening matters, while
#   running it as root would leave the TUI's state dirs root-owned.
# Args:
#   $1  src (string): "source" or "binary"
#   $2  tail (string): "" (default variant) or a suffix for variant-distinct
#       tags like "basic"/"full-binary"/"basic-binary"
# Globals:
#   TUI_IMG (string): namespace of the committed image
#   LATEST_VERSION (string): version tag suffix
# Outputs:
#   Commits ${TUI_IMG}:latest (or :<tail>) + version tag
# ---------------------------------------------------------------------------
compose_tui() {
  local src="$1" tail="$2" container ocbin_image
  container=$(buildah from "${TUI_BASE_IMG}")
  ocbin_image=$(ocbin_for "$src")
  merge_payload "$container" "$ocbin_image" /usr/local/bin/opencode /usr/local/bin/opencode

  buildah config --env HOME=/home/opencode "$container"
  buildah config --env PATH=/usr/local/bin:/usr/bin:/bin "$container"
  buildah run --user opencode "$container" -- bash -ec '
    mkdir -p /home/opencode/workspace /home/opencode/.cache/opencode \
      /home/opencode/.local/share/opencode /home/opencode/.local/state/opencode \
      /home/opencode/.config/opencode /home/opencode/.npm
    chmod -R o+X /home/opencode
    chmod -R o+rwX /home/opencode/workspace /home/opencode/.cache/opencode \
      /home/opencode/.local/share/opencode /home/opencode/.local/state/opencode \
      /home/opencode/.config/opencode /home/opencode/.npm
    chmod o+rwx /home/opencode/.local /home/opencode/.local/share \
      /home/opencode/.config /home/opencode/.cache
  '
  buildah config --user opencode "$container"
  buildah config --workingdir /home/opencode/workspace "$container"
  buildah config --entrypoint '["opencode"]' "$container"

  if [ -z "${tail}" ]; then
    buildah commit --rm "$container" "${TUI_IMG}:latest"
    buildah tag "${TUI_IMG}:latest" "${TUI_IMG}:${LATEST_VERSION}"
  else
    buildah commit --rm "$container" "${TUI_IMG}:${tail}"
    buildah tag "${TUI_IMG}:${tail}" "${TUI_IMG}:${tail}-${LATEST_VERSION}"
  fi
  ok " TUI image ready: ${TUI_IMG}:${tail:-latest}"
}

# ---------------------------------------------------------------------------
# ensure_all_layers(<stack>, <src>)
#
# Description: orders ensure() over every layer a variant needs. Everything
#   except rusttools and pgassets is shared by both stacks; those two only build
#   when the stack is full, which is now the whole full/basic difference.
#   pydex is shared because it is the image's only Python and mcp + ansible
#   both pin to it.
# Args:
#   $1  stack (string): "full" or "basic"
#   $2  src (string): "source" or "binary"
# Outputs:
#   Side effect of ensure(): each required layer image present locally/pushed
# ---------------------------------------------------------------------------
ensure_all_layers() {
  local stack="$1" src="$2"
  ensure base "${BASE_IMG}"
  ensure tui_base "${TUI_BASE_IMG}"
  ensure uvbin "${UVBIN_IMG}"
  # pydex is shared, not full-only: it is the one Python the image is allowed to
  # use, and both mcp and ansible pin their venvs to it. Ordering matters --
  # pydex has to exist before the two layers that build FROM it.
  ensure pydex "${PYDEX_IMG}"
  ensure gobin "${GOBIN_IMG}"
  ensure mcp "${MCP_IMG}"
  ensure ansible "${ANSIBLE_IMG}"
  ensure devtools "${DEVTOOLS_IMG}"
  if [ "${stack}" = full ]; then
    ensure rusttools "${RUST_IMG}"
    ensure pgassets "${PGA_IMG}"
  fi
  ensure "ocbin_${src}" "$(ocbin_for "$src")"
}

# ---------------------------------------------------------------------------
# usage()
#
# Description: prints the valid subcommands and variant env knobs.
# Outputs:
#   Usage text to stderr
# Returns:
#   Exits 2 (usage error)
# ---------------------------------------------------------------------------
usage() {
  echo "usage: buildah-build.sh <layers|server|tui|build>" >&2
  echo "         STACK=full|basic  SRC=source|binary  TAIL=full-binary|basic|basic-binary" >&2
  exit 2
}

# ---------------------------------------------------------------------------
# Dispatch
#   layers  - ensure all layer images for the variant (build + push missing)
#   server  - compose the opencode-server image only
#   tui     - compose the opencode-tui image only
#   build   - layers, then compose both finals (the publish path)
# ---------------------------------------------------------------------------
case "${1:-}" in
layers)
  ensure_all_layers "${STACK:-full}" "${SRC:-source}"
  ;;
server)
  compose_server "${STACK:-full}" "${SRC:-source}" "${TAIL:-}"
  ;;
tui)
  compose_tui "${SRC:-source}" "${TAIL:-}"
  ;;
build)
  ensure_all_layers "${STACK:-full}" "${SRC:-source}"
  compose_server "${STACK:-full}" "${SRC:-source}" "${TAIL:-}"
  compose_tui "${SRC:-source}" "${TAIL:-}"
  ;;
*)
  usage
  ;;
esac
