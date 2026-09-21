# Security Model & Threat Assessment — fortress seat

Colocated with `ai_fortress.te`. Records the threat model, what the policy actually
controls, the assessed-and-rejected removals, and the residual vectors.
Complements the session log in PROGRESS.md — do not remove grants blind;
the te's inline notes state the same rationale.

## Scope & model

- Model: "mythos-class" = a hostile, high-capability agent running inside the
  seat. Assume breach; the seat is treated as attacker code once it executes.
- This document answers: what does the SELinux module protect, what can a
  hostile agent not do, and what is genuinely out of reach of any module.

## Boundary reality

Container containment is provided by, in order:

1. Rootless podman: keep-id userns (container uid maps to the invocation uid,
   never root), `--share net` bridge pod, pasta for network namespacing.
2. Kernel namespaces + cgroups (user-slice scoped).
3. seccomp (not covered by this module).
4. Up-to-date kernel — user-namespace / kernel bugs are the actual escape
   path against a determined agent, and no SELinux policy prevents a 0-day.

This policy's job is defense-in-depth and value reduction, not a vault.

## What the module controls, honestly

Grant | Effect | Control value
------|--------|--------------
`node_bind` (tcp/udp on `node_t`) | loopback/container-address listener + UDP resolver client binds | Needed by the server at all; coarse (loopback is labeled `node_t` too, so loopback-only can't be expressed)
`name_bind`/`name_connect` on `fortress_port_t` (4096/5005) | in-pod listeners/connects | No arbitrary-port listeners; verified live (5433/15433/5431/6432 blocked, 5432 connects allowed)
`corenet_tcp_connect_http_port` | HTTPS client egress, **port-wide** | The exfil/C2 channel; correct hardening is endpoint pinning, not removal
`corenet_tcp_connect_postgresql_port` | LAN DB connect | Value-hardening (removes a reachable LAN service); not a containment control
`fs_read_cgroup_files` / `kernel_read_system_state` | cgroup + /proc reads | Recon only; required by runtime (AVC-verified)
tmpfs `execute execute_no_trans map` | pip/uv `.local` staging | Required for installs; also an arbitrary-code primitive
`fortress_src_t`/`fortress_cache_t` `manage`+`execute`+`map` | run tools off the workspace/cache | This is a code-execution primitive — by design, but the largest one
`execmem` | JIT (CPython 3.14) | Controls JIT only; arbitrary code exec remains via the writable+executable types above

## Assessed removals (the "can it break out if..." question)

### `execmem` off — cosmetic for containment
JIT-compiled writable-memory execution is the only thing gated. A hostile
agent writes its own payload to a writable+executable type (src/cache/tmpfs)
and executes it — arbitrary code execution survives unchanged. Removing it
breaks JIT tooling without closing code exec. C-grade (build-time JIT-off)
only if the runtime is rebuilt without the JIT first: **rejected for the
current build**.

### DB connect off — value-hardening, not breakout
Pulling `corenet_tcp_connect_postgresql_port` prunes one LAN service. The
sizable issue is that `$PGPASS` is mounted *into* the seat (ai-secure)
alongside the 5432 grant: a hostile agent reads real DB creds and reaches
the DB host. Right fix: don't mount pgpass into untrusted sessions +
remove the connect grant. **Not implemented; recommended with the egress
work.**

### `domain_fd_use` off — breaks the platform (live-tested)
The boolean is required by rootless podman: pasta (network-namespace setup)
needs `fd use` from `container_runtime_t`. With it off, pasta segfaults
(`sig=11`, denying `fd use ... tclass=fd`, "starting some containers:
internal libpod error") and no pod can start. Per-domain fd-use grants are
not expressible. **Rejected with evidence; the module's `fd use` cut stays
cosmetic behind the required boolean.**

## Residual vectors (priority order)

1. **Supply-chain via the workspace** — the host workspace is bind-mounted
   read-write and executable-by-design, with the host user operating in the
   same uid context. A hostile agent can plant `.git/hooks` or build
   artifacts that the host user later executes. **Empirically confirmed**:
   a seat agent told to "edit an inline comment" patched a binary in the tree
   (equal-length byte edit) without protest, then exec'd it and hit the
   `execute` denial. The agent can therefore corrupt workspace content at
   will; it can only be stopped *executing* it directly. SELinux cannot
   distinguish "user wrote" from "agent wrote". Controls: treat workspace
   artifacts as untrusted on the host (git diff hygiene), and the cut below
   on `execute` as defense-in-depth (indirect interpreter execution —
   `bash ./payload` — still works, so this is a portability blocker, not a
   sandbox wall).
2. **Port-wide HTTPS egress** — exfil/C2/download convenience. Remedy:
   pin egress to the provider endpoint (fixed host→IP + destination-scoped
   connect), accepting the loss of provider rotation.
3. **DB value escape** — pgpass + 5432 reachable from the seat. See above.
4. **Kernel/user-ns 0-day** — outside this module's reach; mitigated by
   rootless/keep-id, seccomp, and patching cadence.

## Recommended posture (future work, not yet implemented)

- **A**: drop the DB connect grant + stop mounting pgpass into sessions
  running untrusted models; pin HTTP egress to the provider endpoint.
- **B**: workspace `:ro` mount + remove `execute`/`map` from `fortress_src_t`
  (read source, never run it); keep tmpfs for pip staging.
- **C**: shed `execmem` only alongside a QJIT-off build.

Status as of the posture-B trial: **B-lite** (drop `execute` only, keep
`map`) was live-tested on the fortress host — `git clone` into the workspace
succeeds, a full agent read/edit/summarize flow runs, and the only AVCs
were the intended `{ execute }` denials from a direct binary exec attempt.
Full **B** (also drop `map`) is **falsified**: git's config rewrite mmaps
`.git/config` read-write, so a checkout cannot clone without `map`. B-lite
kept as the surviving cut pending the workflow call (repos whose agents must
exec in-tree tooling — `.venv/bin/*`, `./node_modules/.bin/*`, compiled
targets — will hit `{ execute }` denials).

## Validation coverage

Grants proven in live runs (functional proof or absence-of-AVC under the
enforcing policy): `execmem` (V8 JIT ran, zero execmem AVCs), fork/signal,
tcp/udp socket perms, `name_bind`/`name_connect` (4096/5005), DNS, HTTP
egress, postgresql connect, `node_bind` tcp+udp, container_file_t exec,
`corecmd_exec_bin/shell`, cache `execute`+`map` (uv wheels), cap_userns
(file ops under keep-id), tmpfs execute (pip install), cgroup + system-state
reads, `self:lnk_file` (venv symlinks), user terminals (seat pty),
`container_runtime_t:fifo_file`, and the container->seat transition.
`fortress_src_t:file map` is now empirically required (git config mmap) and
`fortress_src_t:file execute` is now empirically exercised (denied by B-lite,
agent misattributes it as a mount quirk).

Granted but never empirically exercised — the audit trail's open items:

| Grant | te:line | Why unexercised |
|-------|---------|-----------------|
| `self:shm create/destroy/read/write` | 54 | no POSIX shm consumer observed (tmpfs files cover actual needs) |
| `self:process setsched` | 51 | only fires on a priority/scheduler change; nothing did |
| `self:unix_stream_socket` full perms | 140 | in-seat AF_UNIX IPC; no explicit test, no AVCs either way |
| `fortress_*` ioctl allowxperm (TCGETS, FS_IOC_*) | 108-112 | only observed fires: `cp` into src hits non-whitelisted 0x9409 (pre-existing; broaden the whitelist if cp-in-src must work) |
| `kernel_read_system_state` deeper facets | 130 | only meminfo/version verified; uptime/loadavg/etc. untested |

The posture-B trial (drop `execute` + `map`) ran as the recommended
falsification test on the fortress host; outcomes and the surviving B-lite
cut are recorded under "Recommended posture" above.