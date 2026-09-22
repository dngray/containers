# Deployment reference

Host-operational notes for running the container pipelines in this repo.

## SELinux and the opencode build cache

The opencode buildah pipeline bind-mounts the host build cache
(build/opencode/cache) into build containers at /mnt/host_cache. Under SELinux
Enforcing this only works if every file under that cache carries the
`container_file_t` type, which the build-time `container_t` (svirt) domain is
allowed to fully manage.

### Why it breaks

The fortress SELinux policy (`build/ai_fortress/ai_fortress.fc`) labels project
source trees as `fortress_src_t`:

```
HOME_DIR/src(/.*)?          -> fortress_src_t
HOME_DIR/workspace(/.*)?    -> fortress_src_t
```

`fortress_src_t` is intentionally restricted to the runtime
`fortress_agent_t` domain; `container_t` has no access at all. Because the repo
(and therefore `build/opencode/cache`) sits under `$HOME/src` or
`$HOME/workspace`, a `restorecon` run over the tree relabels the cache to
`fortress_src_t`, and every build-container write to the cache is AVC-denied.

Symptom: `apt-get` inside the build fails, e.g.

```
W: chown to _apt:root of directory /mnt/host_cache/apt_cache/partial failed - SetupAPTPartialDirectory (13: Permission denied)
E: Could not open lock file /mnt/host_cache/apt_cache/lock - open (13: Permission denied)
E: Unable to lock directory /mnt/host_cache/apt_cache/
Error: while running runtime: exit status 100
```

with matching audit lines:

```
audit: AVC avc: denied { setattr } for comm="apt-get" name="partial"
  scontext=...:container_t:... tcontext=unconfined_u:object_r:fortress_src_t:s0 tclass=dir
audit: AVC avc: denied { read write } for comm="apt-get" name="lock" tclass=file
```

### Fix on an affected host

Most-specific fcontext rules win over the `src`/`workspace` wildcards, so add a
local override for the cache and re-label it (run as a privileged user; beware
`$HOME` expanding to `/root` — use the literal repo path):

```
sudo semanage fcontext -a -t container_file_t "${HOME}/src/github.com/dngray/containers/build/opencode/cache(/.*)?"
sudo restorecon -RFv "${HOME}/src/github.com/dngray/containers/build/opencode/cache"
```

Verify:

```
ls -Z build/opencode/cache/apt_cache   # want object_r:container_file_t
```

Remove a wrong/local override with `semanage fcontext -d` (no `-t`), e.g.
`sudo semanage fcontext -d "/root/src/.../build/opencode/cache(/.*)?"`, and
confirm with `semanage fcontext -l -C | grep opencode`.

### Guardrail

`buildah-build.sh` runs a pre-flight check (`selinux_cache_guard`): when
`getenforce` is `Enforcing` and the cache resolves to `fortress_src_t`, it
fails fast with the snippet above instead of an opaque `exit status 100`. It
does not attempt the relabel itself — that needs root, and an unattended
build must not prompt for it.

### Policy source

The `container_file_t` exceptions for the known repo layouts live in
`build/ai_fortress/ai_fortress.fc`:

```
HOME_DIR/src/containers/build/opencode/cache(/.*)? gen_context(system_u:object_r:container_file_t,s0)
HOME_DIR/src/github.com/dngray/containers/build/opencode/cache(/.*)? gen_context(system_u:object_r:container_file_t,s0)
HOME_DIR/workspace/github.com/dngray/containers/build/opencode/cache(/.*)? gen_context(system_u:object_r:container_file_t,s0)
```

(`HOME_DIR` matches `$HOME` on any layout, including `/var/home` under
systemd-homed.) Any other checkout of the repo under `~/src` or `~/workspace`
needs a matching local `semanage` override rather than a new `.fc` line.