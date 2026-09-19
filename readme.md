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
