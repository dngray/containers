#!/bin/bash
# tests/run-tests.sh — Fortress regression tests.
#
# Pure shell + jq: the repo has no language toolchain beyond bash/coreutils, so
# a Python harness would add a dependency for no benefit. These tests assert the
# behaviour that is easy to break silently:
#
#   * no credential is ever exported into the launcher environment
#   * provider keys land in auth.json (0600), never in the podman argv
#   * the security baseline survives in every agent/role combination
#   * v1 and v2 differ only in port, probe path, and server argv
#   * the workspace path mapping rejects unlabelled roots
#
# Run: ./tests/run-tests.sh   (or `just fortress-test`)

set -u

TESTS_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd "$TESTS_DIR/.." && pwd)
FORTRESS_DIR="$REPO_ROOT/apps/fortress"
EXEC="$FORTRESS_DIR/fortress-exec"

PASS=0
FAIL=0

pass() {
  PASS=$((PASS + 1))
  printf '  \033[32mPASS\033[0m %s\n' "$1"
}

fail() {
  FAIL=$((FAIL + 1))
  printf '  \033[31mFAIL\033[0m %s\n' "$1"
  [ -n "${2:-}" ] && printf '       %s\n' "$2"
}

check() {
  # check <description> <condition-result> [detail]
  if [ "$2" -eq 0 ]; then pass "$1"; else fail "$1" "${3:-}"; fi
}

# Stub the two tools that would otherwise do real work or reach a host service.
# realpath/id/date must stay real: the executor uses realpath for its own
# self-location, and stubbing it breaks the script under test rather than
# exercising it.
#
# podman is deliberately SILENT (it only needs to answer "does this pod
# exist?" with an exit status). A stub that echoed to stdout would leak into the
# captured plan and be mistaken for a leaked secret.
install_stubs() {
  mkdir -p "$1/bin"
  printf '#!/bin/sh\necho %s\n' "$2" >"$1/bin/gopass"
  printf '#!/bin/sh\nexit 0\n' >"$1/bin/podman"
  chmod +x "$1/bin/gopass" "$1/bin/podman"
}

# Build a seat plan with stubbed secrets so no gopass/podman call happens.
# Prints the resolved podman argv, one shell-escaped argument per line.
plan() {
  _agent=$1
  _role=$2
  _api=${3:-v1}
  _variant=${4:-latest}

  # Reuse a caller-provided HOME when set, so two invocations differ only by
  # the arguments under test (mount paths leak the tempdir name into argv).
  _home=${PLAN_HOME:-}
  if [ -z "$_home" ]; then
    _home=$(mktemp -d)
    mkdir -p "$_home/src/proj" "$_home/bin"
    install_stubs "$_home" stubvalue
    _own_home=1
  else
    mkdir -p "$_home/src/proj" "$_home/bin"
    install_stubs "$_home" stubvalue
    _own_home=0
  fi

  (
    PATH="$_home/bin:$PATH"
    HOME="$_home"
    FORTRESS_HOME="$_home"
    FORTRESS_PATH="$_home/src/proj"
    OPENCODE_API="$_api"
    OPENCODE_VARIANT="$_variant"
    export PATH HOME FORTRESS_HOME FORTRESS_PATH OPENCODE_API OPENCODE_VARIANT
    REG_URL="registry.example" bash "$EXEC" "$_agent" "$_role" --print-plan 2>/dev/null
  )
  [ "$_own_home" -eq 1 ] && rm -rf "$_home"
  return 0
}

echo "fortress tests"
echo

# ---------------------------------------------------------------------------
# 1. Security baseline present in every seat
# ---------------------------------------------------------------------------
echo "security baseline"
# podman accepts these as either "--opt=value" or two argv tokens; the
# executor uses the two-token form, so assert on the pairs the executor
# actually emits rather than one canonical spelling.
BASELINE=(
  "--cap-drop=ALL"
  "--log-driver=none"
  "--user"
)
# Identity mapping differs by agent: the pod-backed agents (opencode, goose)
# inherit the host uid and add the host's supplementary groups; standalone
# aider has no pod and instead maps the whole id range with --userns keep-id.
# Both are identity-preserving, which is what the baseline actually requires.
BASELINE_POD=("--group-add keep-groups")
BASELINE_STANDALONE=("--userns keep-id")
# Two-token options: assert the flag and its value appear adjacently.
BASELINE_PAIRS=(
  "--security-opt:no-new-privileges"
  "--security-opt:label=type:fortress_agent_t"
)
for combo in "opencode server" "opencode tui" "goose server" "goose session" "aider "; do
  set -- $combo
  agent=$1
  role=${2:-}
  out=$(plan "$agent" "$role" v1 latest)
  ok_all=1
  for flag in "${BASELINE[@]}"; do
    case "$out" in
    *"$flag"*) ;;
    *)
      fail "$agent ${role:-<none>}: baseline has $flag"
      ok_all=0
      break
      ;;
    esac
  done
  if [ "$ok_all" -eq 0 ]; then continue; fi
  case "$agent" in
  aider)
    identity=("${BASELINE_STANDALONE[@]}")
    ;;
  *)
    identity=("${BASELINE_POD[@]}")
    ;;
  esac
  for flag in "${identity[@]}"; do
    case "$out" in
    *"$flag"*) ;;
    *)
      fail "$agent ${role:-<none>}: baseline has $flag"
      ok_all=0
      break
      ;;
    esac
  done
  if [ "$ok_all" -eq 0 ]; then continue; fi
  for pair in "${BASELINE_PAIRS[@]}"; do
    k=${pair%%:*}
    v=${pair#*:}
    # Normalise whitespace so "a  b" and "a b" compare equal.
    squashed=$(printf '%s' "$out" | tr -s '[:space:]' ' ')
    case "$squashed" in
    *"$k $v"*) ;;
    *)
      fail "$agent ${role:-<none>}: baseline has $k $v"
      ok_all=0
      break
      ;;
    esac
  done
  [ "$ok_all" -eq 0 ] && continue
  pass "$agent ${role:-<none>}: full security baseline"
done

# ---------------------------------------------------------------------------
# 2. No provider key ever reaches the podman argv for opencode
#    (opencode authenticates from the bind-mounted auth.json instead)
# ---------------------------------------------------------------------------
echo
echo "credential scoping"
for role in server tui; do
  out=$(plan opencode "$role" v1 latest)
  leaked=""
  for key in OPENROUTER_API_KEY OPENAI_API_KEY ANTHROPIC_API_KEY; do
    case "$out" in
    *"$key="*) leaked="$key" ;;
    esac
  done
  [ -z "$leaked" ] &&
    pass "opencode $role: no provider key in argv" ||
    fail "opencode $role: $leaked leaked into the container argv"
done

# The server bind-password IS expected as a container env var: opencode has no
# config or auth-store representation for it. Guard the reason, not the absence.
for role in server tui; do
  out=$(plan opencode "$role" v1 latest)
  case "$out" in
  *OPENCODE_SERVER_PASSWORD=*) pass "opencode $role: bind-password passed explicitly (no config home)" ;;
  *) fail "opencode $role: bind-password missing" "TUI attach would fail" ;;
  esac
done

# goose speaks the OpenAI-compatible protocol regardless of upstream, so the
# env var NAME is always OPENAI_API_KEY. Which key VALUE lands there depends on
# GOOSE_MODE, and the seat must never hold both providers' credentials. The
# plan is redacted, so assert the env wiring here and the unredacted value
# selection directly against the agent file below.
for mode in nanogpt openrouter; do
  home=$(mktemp -d)
  mkdir -p "$home/src/proj" "$home/bin"
  install_stubs "$home" stubvalue
  # Distinguishable secrets so a wrong-key regression is visible.
  printf '#!/bin/sh\ncase "$*" in *openrouter*) echo OR-KEY ;; *openai*) echo OA-KEY ;; *) echo OTHER ;; esac\n' \
    >"$home/bin/gopass"
  chmod +x "$home/bin/gopass"

  out=$(
    PATH="$home/bin:$PATH" HOME="$home" FORTRESS_HOME="$home" \
      FORTRESS_PATH="$home/src/proj" \
      GOOSE_MODE="$mode" REG_URL=registry.example \
      bash "$EXEC" goose server --print-plan 2>/dev/null
  )
  rm -rf "$home"

  case "$mode" in
  nanogpt) want=OA-KEY ;;
  openrouter) want=OR-KEY ;;
  esac
  # The plan is redacted, so assert the wiring (the flag is present with the
  # right key's name) and, separately, that no raw secret leaked into it.
  case "$out" in
  *"OPENAI_API_KEY=REDACTED"*) got=0 ;;
  *) got=1 ;;
  esac
  check "goose $mode: plan carries OPENAI_API_KEY (redacted)" "$got"

  case "$out" in
  *"$want"*) leak=1 ;;
  *) leak=0 ;;
  esac
  check "goose $mode: plan does NOT leak the key value" \
    "$([ "$leak" -eq 0 ] && echo 0 || echo 1)"
done

# Unredacted value selection: source goose.sh directly and inspect the env it
# would hand podman. This is the assertion the redacted plan cannot make --
# that GOOSE_MODE picks the right secret and that only one provider is present.
for mode in nanogpt openrouter; do
  home=$(mktemp -d)
  mkdir -p "$home/src/proj" "$home/bin"
  printf '#!/bin/sh\ncase "$*" in *openrouter*) echo OR-KEY ;; *openai*) echo OA-KEY ;; *) echo OTHER ;; esac\n' \
    >"$home/bin/gopass"
  printf '#!/bin/sh\nexit 0\n' >"$home/bin/podman"
  chmod +x "$home/bin/gopass" "$home/bin/podman"

  # The agent file is sourced the way fortress-exec sources it: with the shared
  # libs and the seat context already in place.
  seat_env=$(
    PATH="$home/bin:$PATH" HOME="$home" FORTRESS_HOME="$home" GOOSE_MODE="$mode" \
      REG_URL=registry.example \
      ROLE=server POD_NAME=fortress-pod-proj PROJECT_ID=proj \
      TARGET_PATH="$home/src/proj" REL_PATH="proj" \
      CUR_UID=1000 CUR_GID=1000 \
      bash -c '
        . "$1/lib/cli.sh"
        . "$1/lib/fortress.sh"
        . "$2/apps/fortress/agents/goose.sh"
        printf "%s\n" "${F_EXTRA_FLAGS[@]}"
      ' _ "$REPO_ROOT" "$REPO_ROOT" 2>&1
  )
  rm -rf "$home"

  case "$mode" in
  nanogpt) want=OA-KEY ;;
  openrouter) want=OR-KEY ;;
  esac
  other=OR-KEY
  [ "$want" = "OR-KEY" ] && other=OA-KEY

  case "$seat_env" in
  *"OPENAI_API_KEY=$want"*) got=0 ;;
  *) got=1 ;;
  esac
  check "goose $mode: seat env holds $want" "$got" \
    "env was: $(printf '%s' "$seat_env" | tr '\n' ' ')"

  case "$seat_env" in
  *"$other"*) leak=1 ;;
  *) leak=0 ;;
  esac
  check "goose $mode: seat env does NOT hold $other" \
    "$([ "$leak" -eq 0 ] && echo 0 || echo 1)"
done

# A plan is a debugging artifact that reaches scrollback, CI logs and bug
# reports, so every secret-bearing flag must be masked.
for combo in "opencode server" "opencode tui" "goose server" "goose session" "aider "; do
  set -- $combo
  out=$(plan "$1" "${2:-}" v1 latest)
  case "$out" in
  *"REDACTED"*) found=0 ;;
  *) found=1 ;;
  esac
  check "$1 ${2:-<none>}: plan redacts secrets" "$found" "no REDACTED marker in plan"

  case "$out" in
  *stubvalue*) raw=1 ;;
  *) raw=0 ;;
  esac
  check "$1 ${2:-<none>}: plan has no raw secret value" \
    "$([ "$raw" -eq 0 ] && echo 0 || echo 1)" "gopass stub value appeared verbatim"
done

# Planning must not require podman on PATH or a live pod: it exists to render
# an argv before the first launch. Regression guard for agents that gated the
# pod check unconditionally, which made `just fortress-plan` fail on a clean host.
_nopm=$(mktemp -d)
mkdir -p "$_nopm/src/proj" "$_nopm/bin"
printf '#!/bin/sh\necho stubvalue\n' >"$_nopm/bin/gopass"
chmod +x "$_nopm/bin/gopass"
for combo in "opencode server" "opencode tui" "goose server" "goose session"; do
  set -- $combo
  pout=$(
    PATH="$_nopm/bin:/usr/bin:/bin" HOME="$_nopm" FORTRESS_HOME="$_nopm" \
      FORTRESS_PATH="$_nopm/src/proj" \
      OPENCODE_API=v1 REG_URL=registry.example \
      bash "$EXEC" "$1" "$2" --print-plan 2>/dev/null
  )
  case "$pout" in
  "" | *"command not found"* | *"Launch via fortress"*) rc=1 ;;
  *) rc=0 ;;
  esac
  check "$1 $2: plan renders without podman or a live pod" "$rc" \
    "$(printf '%s' "$pout" | head -1)"
done
rm -rf "$_nopm"

# A long-lived shell (or one predating a systemd-homed migration) can carry a
# stale HOME=/home/<user> while passwd says /var/home/<user>. The .fc labels
# are keyed on passwd's HOME_DIR, so the path checks must use passwd too.
_stale=$(mktemp -d)
mkdir -p "$_stale/bin" "$_stale/home/.local/bin" "$_stale/newroot/src/proj"
printf '#!/bin/sh\necho stubvalue\n' >"$_stale/bin/gopass"
chmod +x "$_stale/bin/gopass"
sout=$(
  PATH="$_stale/bin:/usr/bin:/bin" \
    HOME="$_stale/home" FORTRESS_HOME="$_stale/newroot" \
    FORTRESS_PATH="$_stale/newroot/src/proj" OPENCODE_API=v1 REG_URL=registry.example \
    bash "$EXEC" opencode server --print-plan 2>/dev/null
)
check "stale \$HOME: path under the passwd home still plans" \
  "$([ -n "$sout" ] && printf '%s' "$sout" | grep -q 'fJail\|/home/opencode/workspace' && echo 0 || echo 1)" \
  "$(printf '%s' "$sout" | head -1)"
rm -rf "$_stale"

# ---------------------------------------------------------------------------
# 3. v1 vs v2 differ only in port, probe path and server argv
# ---------------------------------------------------------------------------
echo
echo "v1 / v2 divergence"
# Pin one HOME across both runs: otherwise the mktemp path leaks into the
# mount arguments and the comparison fails for a reason unrelated to v1/v2.
DIFF_HOME=$(mktemp -d)
PLAN_HOME=$DIFF_HOME
v1=$(plan opencode server v1 latest)
v2=$(plan opencode server v2 latest)

# Ports and the server argv must change.
case "$v1" in *--port\ 4096*) p1=0 ;; *) p1=1 ;; esac
case "$v2" in *--port\ 49374*) p2=0 ;; *) p2=1 ;; esac
check "v1 server binds 4096" "$p1"
check "v2 server binds 49374" "$p2"

# Everything else must be identical once the port token is normalised away.
norm() { printf '%s' "$1" | sed -E 's/(4096|49374)/PORT/g'; }
[ "$(norm "$v1")" = "$(norm "$v2")" ] &&
  pass "v1/v2 server plans identical apart from the port" ||
  fail "v1/v2 server plans differ beyond the port" \
    "$(diff <(printf '%s\n' "$(norm "$v1")") <(printf '%s\n' "$(norm "$v2")") | head -20)"

# The TUI probe path is the second documented difference.
t1=$(plan opencode tui v1 latest)
t2=$(plan opencode tui v2 latest)
case "$t1" in *"/api/info"*) q1=1 ;; *) q1=0 ;; esac
case "$t2" in *"/api/info"*) q2=0 ;; *) q2=1 ;; esac
check "v1 TUI probes / (not /api/info)" "$q1"
check "v2 TUI probes /api/info" "$q2"
rm -rf "$DIFF_HOME"
unset PLAN_HOME

# ---------------------------------------------------------------------------
# 4. Workspace path mapping
# ---------------------------------------------------------------------------
echo
echo "workspace path mapping"
# shellcheck source=../lib/fortress.sh
. "$REPO_ROOT/lib/fortress.sh"
thome=$(mktemp -d)

rel_ok() {
  _got=$(FORTRESS_HOME="$thome" fortress_rel_path "$thome/src/foo" 2>/dev/null)
  [ "$_got" = "foo" ]
}
rel_rejects_outside() {
  _got=$(FORTRESS_HOME="$thome" fortress_rel_path "$thome/other/foo" 2>/dev/null)
  [ -z "$_got" ]
}
# ~/srcfoo must not be treated as inside ~/src (prefix without separator).
rel_rejects_prefix_trap() {
  _got=$(FORTRESS_HOME="$thome" fortress_rel_path "$thome/srcfoo/x" 2>/dev/null)
  [ -z "$_got" ]
}
check "maps ~/src/<rel>" "$(rel_ok && echo 0 || echo 1)"
check "rejects an unlabelled root" "$(rel_rejects_outside && echo 0 || echo 1)"
check "rejects the ~/srcfoo prefix trap" "$(rel_rejects_prefix_trap && echo 0 || echo 1)"

# A symlinked home must still match: SELinux labels inodes, and restorecon
# follows the symlink, so /home/<user>/src and /var/home/<user>/src are the
# same labelled tree. A textual prefix match wrongly rejected it.
shome=$(mktemp -d)
mkdir -p "$shome/var/src/proj"
ln -s "$shome/var" "$shome/home"
smatch=$(FORTRESS_HOME="$shome/home" fortress_rel_path "$shome/var/src/proj" 2>/dev/null)
check "resolves a symlinked home to the same physical tree" \
  "$([ "$smatch" = "proj" ] && echo 0 || echo 1)" "got '$smatch'"
sreject=$(FORTRESS_HOME="$shome/home" fortress_rel_path "$shome/elsewhere/proj" 2>/dev/null)
check "still rejects a path outside a symlinked home" \
  "$([ -z "$sreject" ] && echo 0 || echo 1)" "got '$sreject'"
rm -rf "$shome"

WORKSPACE_OK=$(FORTRESS_HOME="$thome" fortress_rel_path "$thome/workspace/deep/proj" 2>/dev/null)
check "maps ~/workspace/<rel>" \
  "$([ "$WORKSPACE_OK" = "deep/proj" ] && echo 0 || echo 1)" "got '$WORKSPACE_OK'"
rm -rf "$thome"

# ---------------------------------------------------------------------------
# 5. auth.json writer: 0600, valid JSON, no key material in argv
# ---------------------------------------------------------------------------
echo
echo "auth.json writer"
ahome=$(mktemp -d)
(
  HOME="$ahome"
  FORTRESS_HOME="$ahome"
  FORTRESS_CONFIG="$ahome/.config/fortress"
  export HOME FORTRESS_HOME FORTRESS_CONFIG
  . "$REPO_ROOT/lib/fortress.sh"
  OPENROUTER_API_KEY=or-key-value
  OPENAI_API_KEY=oa-key-value
  ANTHROPIC_API_KEY=an-key-value
  fortress_write_auth_json
)
ah="$ahome/.config/fortress/opencode/share/auth.json"
[ -f "$ah" ] && pass "auth.json written" || fail "auth.json missing"
check "auth.json mode is 0600" \
  "$([ "$(stat -c '%a' "$ah" 2>/dev/null || stat -f '%Lp' "$ah")" = "600" ] && echo 0 || echo 1)" \
  "mode $(stat -c '%a' "$ah" 2>/dev/null || stat -f '%Lp' "$ah")"
check "auth.json is valid JSON" \
  "$(jq -e . "$ah" >/dev/null 2>&1 && echo 0 || echo 1)"
check "auth.json has all three providers" \
  "$([ "$(jq -r 'keys | length' "$ah" 2>/dev/null)" = "3" ] && echo 0 || echo 1)" \
  "$(jq -r 'keys' "$ah" 2>/dev/null)"
check "auth.json entries are type=api" \
  "$([ "$(jq -r '[.[] | select(.type == "api")] | length' "$ah" 2>/dev/null)" = "3" ] && echo 0 || echo 1)"
rm -rf "$ahome"

# ---------------------------------------------------------------------------
# 6. Launcher must not export provider keys into the zellij environment
# ---------------------------------------------------------------------------
echo
echo "launcher credential hygiene"
if grep -Eq '^[[:space:]]*export .*(OPENROUTER_API_KEY|OPENAI_API_KEY|ANTHROPIC_API_KEY)' "$FORTRESS_DIR/fortress"; then
  fail "fortress exports a provider key" "grep found an export line"
else
  pass "fortress exports no provider key"
fi

# ---------------------------------------------------------------------------
# 7. Naming: no legacy identifiers anywhere in the tracked tree
# ---------------------------------------------------------------------------
echo
echo "naming"
# This file necessarily contains the old names as search patterns, so it is
# excluded alongside the migration notes. Everything else must be clean.
legacy=$(cd "$REPO_ROOT" && git grep -lI -e 'ai-secure' -e 'code-fortress' -e 'ai_fortress' -e 'ai-fortress' -- \
  ':!readme.md' ':!justfile' ':!apps/opencode/buildah-build.sh' ':!tests/run-tests.sh' 2>/dev/null)
if [ -z "$legacy" ]; then
  pass "no legacy names outside intentional migration notes"
else
  fail "legacy names still present" "$legacy"
fi

# The SELinux module renames.
check "policy_module is selinux-fortress" \
  "$(grep -q '^policy_module(selinux-fortress, 1.0)$' "$FORTRESS_DIR/selinux/v1/selinux-fortress.te" && echo 0 || echo 1)"
check "policy_module is selinux-aerc" \
  "$(grep -q '^policy_module(selinux-aerc, 1.0.0)$' "$REPO_ROOT/apps/aerc/selinux-aerc.te" && echo 0 || echo 1)"
check "policy_module is selinux-snapclient" \
  "$(grep -q '^policy_module(selinux-snapclient, 1.0.0)$' "$REPO_ROOT/apps/snapclient/selinux-snapclient.te" && echo 0 || echo 1)"

# Declared types must be unchanged: the module rename must not renumber the
# types that the podman --security-opt labels and the quadlet units reference.
check "fortress types unchanged" \
  "$(grep -q '^type fortress_agent_t;$' "$FORTRESS_DIR/selinux/v1/selinux-fortress.te" && echo 0 || echo 1)"
check "aerc types unchanged" \
  "$(grep -q '^type aerc_t;$' "$REPO_ROOT/apps/aerc/selinux-aerc.te" && echo 0 || echo 1)"
check "snapclient type unchanged" \
  "$(grep -q '^type snapclient_t;$' "$REPO_ROOT/apps/snapclient/selinux-snapclient.te" && echo 0 || echo 1)"

# ---------------------------------------------------------------------------
# 8. v1/v2 policy inputs: only .ports may differ
# ---------------------------------------------------------------------------
echo
echo "policy source parity"
for f in selinux-fortress.te selinux-fortress.fc selinux-fortress.spec; do
  if cmp -s "$FORTRESS_DIR/selinux/v1/$f" "$FORTRESS_DIR/selinux/v2/$f"; then
    pass "v1 == v2: $f"
  else
    fail "v1 != v2: $f" "$(diff -u "$FORTRESS_DIR/selinux/v1/$f" "$FORTRESS_DIR/selinux/v2/$f" | head)"
  fi
done
if cmp -s "$FORTRESS_DIR/selinux/v1/selinux-fortress.ports" "$FORTRESS_DIR/selinux/v2/selinux-fortress.ports"; then
  fail "v1/v2 .ports are identical" "the API port should differ"
else
  pass "v1/v2 .ports differ (the API port)"
fi

echo
echo "---------------------------------------"
printf 'passed: %d   failed: %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
