# Containers

Just the containers I use.

## Repo layout

```
apps/          per-service scripts (aerc, crowdin, davmail, goose, imapfilter,
               neovim, opencode, snapclient, tftp) — the `just` recipes call these
bin/           repo-side tooling (code-fortress, ai-secure, build-selinux,
               create-rpm, debian-build-neovim)
build/         build context directories (Containerfiles, SELinux sources)
compose/       Docker Compose stacks (traefik, vaultwarden, syncthing, flexo, …)
gvisor/        gVisor runsc runtime
layouts/       zellij layouts for code-fortress (aider/opencode/goose)
lib/           shared bootstrap library (lib/cli.sh: colors, env policy, helpers)
systemd/       quadlet unit templates
```

Everything runs through `just` (`just` alone prints the grouped command list).
Scripts locate the repo themselves (`REPO_ROOT`) — no env var needed. The only
thing installed on the host is `~/.local/bin/code-fortress`, symlinked into this
repo; it injects `bin/` onto PATH so `ai-secure` resolves inside the fortress.

### Launching a fortress

```
code-fortress <path> [aider|opencode|goose] [latest|full-binary|basic-binary] [v1|v2]
```

The last three are optional; `opencode`, `latest` and `v2` are the defaults, so
the common case is just `code-fortress . opencode latest`. The variant is
opencode-only, and the API generation is a separate axis that selects the
config, the SELinux policy, the port and the launcher wiring — it does not
change the image variant. Both can also come from the environment
(`OPENCODE_VARIANT`, `OPENCODE_API`), with the argument taking precedence.

`v2` is the current generation and the default; `v1` stays selectable for a
legacy seat. The launcher probes for the selected generation's image before it
creates the pod or fetches any secret, so an unbuilt generation fails with a
message naming the build recipes rather than a half-started seat.

The two generations are not interchangeable at build time: each upstream tag
declares its own bun version (`1.3.14` on v1 tags, `1.4.2` on v2), and the build
refuses to continue if the checked-out tag and the selected bun image disagree.

## Fortress DB access

Per-project Postgres credentials, if the agent should reach a database. Create
the file before launching the seat:

```
~/.config/ai-fortress/opencode/<project>/pgpass.env   # chmod 600, dotenv
```

```
PGHOST=192.168.52.x
PGPORT=5432
PGUSER=<user>
PGPASSWORD=<password>
PGDATABASE=<db>
```

It must be set (a launch without it simply skips the DB mount). Inside the seat
the file lands at `~/.pgpass.env`; source it before psql:

```sh
set -a; . ~/.pgpass.env; set +a
psql
```
