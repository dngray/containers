# SillyTavern

Single rootless Podman **quadlet** running the official upstream image
(`ghcr.io/sillytavern/sillytavern:latest`). No build step: the image is pulled
straight from the GitHub Container Registry, and all state lives in your home
directory.

## Host paths

| Host path | Container path |
|---|---|
| `~/.config/sillytavern` | `/home/node/app/config` |
| `~/.local/share/sillytavern/data` | `/home/node/app/data` |
| `~/.local/share/sillytavern/plugins` | `/home/node/app/plugins` |
| `~/.local/share/sillytavern/extensions` | `/home/node/app/public/scripts/extensions/third-party` |

All four are mounted `:Z` (private SELinux relabel) because they belong to this
container only.

## Commands

```bash
# Pull the upstream image
just st-pull

# Create host dirs, install the quadlet, start the service
just st

# Stop the service
just st-down

# Remove the container and image (host config/data are kept)
just st-clean
```

`just st` symlinks `systemd/sillytavern/sillytavern.container` into
`~/.config/containers/systemd/` (if nothing is there yet) and runs
`systemctl --user daemon-reload` before starting `sillytavern.service`.

The UI is published on `http://127.0.0.1:8000` only. Do not expose it to the
internet without a reverse proxy and authentication.

## Networking

```ini
PublishPort=127.0.0.1:8000:8000
Network=pasta:--host-lo-to-ns-lo
```

Rootless Podman uses `pasta`, which cannot deliver a `127.0.0.1` source address
into the container — the guest would drop it and could not route replies back.
Without `--host-lo-to-ns-lo` pasta rewrites the source to a non-loopback
address, and because Podman copies the host's addresses into the guest
(`--config-net`), a browser on the host arrives at SillyTavern as e.g.
`192.168.31.20` and the stock whitelist rejects it. The option keeps host
loopback connections looking like `127.0.0.1` inside the container, so no
`config.yaml` edit is needed.

The publish address is what decides LAN exposure, not the container itself:
`127.0.0.1:8000:8000` is host-only, `8000:8000` would bind every interface.

## User mapping

The quadlet runs rootless with:

```ini
UserNS=keep-id
Environment=PUID=%U
Environment=PGID=%G
```

`%U`/`%G` are systemd specifiers resolved to the UID/GID of the user running
the user manager, and `keep-id` maps those IDs into the container unchanged.
The image's entrypoint then runs the server as that user, so files created in
the mounted directories are owned by **you** — never by root or a subuid. This
is upstream's PUID/PGID mode, made correct for rootless Podman.

## First run

SillyTavern copies `default/config.yaml` into `~/.config/sillytavern/config.yaml`
on first start. Edit it there, then:

```bash
systemctl --user restart sillytavern.service
```

User data (characters, chats, settings) lands in
`~/.local/share/sillytavern/data`.

## Updating

The image tag is `latest` and the unit sets `AutoUpdate=registry`:

```bash
podman auto-update                       # pull + restart if a new image exists
systemctl --user restart sillytavern.service
```

`podman auto-update` requires the `podman-auto-update.timer` user timer if you
want it to run automatically.

## Logs and health

```bash
podman logs -f sillytavern
journalctl --user -u sillytavern.service -f
podman inspect --format '{{.State.Health.Status}}' sillytavern
```

The healthcheck uses SillyTavern's heartbeat file, enabled by
`SILLYTAVERN_HEARTBEATINTERVAL=30`.

## Troubleshooting

- **Blocked connection from your host's LAN address** — the whitelist is seeing
  pasta's rewritten source address, not the real client. Confirm the unit still
  has `Network=pasta:--host-lo-to-ns-lo`, then recreate the container (network
  settings are fixed at creation):
  ```bash
  just st-down && just st
  ```
  If your `pasta` is too old for that flag, add the address to `whitelist` in
  `~/.config/sillytavern/config.yaml` instead (a CIDR such as
  `192.168.31.0/24` survives DHCP changes) and restart the service.
- **Unit not found** — run `just st` once (or `systemctl --user daemon-reload`)
  so the quadlet generator picks up the unit.
- **Permission denied on a mount** — the directory must be writable by your
  user; the quadlet runs as you, so `chown -R "$(id -u):$(id -g)"` the four host
  paths if they were created by something else.

`just st-clean` only removes the container and image; it never touches
`~/.config/sillytavern` or `~/.local/share/sillytavern`.
