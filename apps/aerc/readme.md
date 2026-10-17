# Aerc Mail Pod

The `aerc-mail.pod` is a net-shared Podman pod holding three containers:

| Container | Role |
|---|---|
| `aerc-ui` | Interactive aerc TUI (reads/writes mail over IMAP/SMTP, notmuch, gopass) |
| `aerc-sync` | Headless mbsync + goimapnotify automation daemon |
| `aerc-bridge` | Proton Mail Bridge — local SMTP/IMAP gateway to your Proton account |

Because the pod shares a single network namespace, `aerc-ui` and `aerc-sync`
reach the bridge on `127.0.0.1` — SMTP on `25`, IMAP on `143`. The bridge
port-forwards those to its own internal `1025`/`1143` via `socat`. None of the
bridge ports are published to the host; only the pod's own containers use it.

The bridge is built **from source** (only trusting Proton's official
`ProtonMail/proton-bridge` source plus the vendored entrypoint in
`build/aerc-bridge/`), pinned to a specific upstream release for
reproducibility.

## PGP state (Sequoia)

Both `aerc-ui` and `aerc-sync` run Sequoia's GnuPG shim as their `gpg`
(`gpg-from-sq`; the images also ship `sq` and `sqop`). Two host directories are
mounted read-write into both containers:

- `~/.gnupg` — GnuPG state. `gpg-sq` delegates secret key operations to the
  host `gpg-agent` (the agent sockets are passed through as well), so secret
  key material never enters the container. `gpg-from-sq` only diverts
  `/usr/bin/gpg` to `gpg-sq`; the rest of the real GnuPG stack stays installed
  because `gopass` depends on `gnupg`. That suits everyone: `gopass` reaches
  Sequoia through the diverted `gpg`, and chameleon still has the `gpgconf` it
  needs to locate the agent's socket and the `gpg-agent` to start one.
- `~/.local/share/pgp.cert.d` — Sequoia's certificate store, and the default
  store for both `sq` and `gpg-sq` while `GNUPGHOME` stays at its default.

`sq pki link add --cert <FPR> --email <EMAIL>` records a non-exportable
certification in the certificate store, and that link is what makes aerc — and
notmuch — treat a recipient's key as usable. Run it from aerc's `Ctrl+T` shell
inside the container or on the host: it is the same store either way, and it
survives container recreation. Because the type is already allowed by the
policy (`data_home_t`), the mounts stay plain `:rw` — adding `:z`/`:Z` would
relabel a store the host's own `sq`/`gpg-sq` also uses.

## Build & start

```bash
# Build the UI, sync, and Proton bridge images
just aerc-build

# Pin the upstream release instead of tracking the latest tag
just aerc-build 0.22.0
just aerc-build master

# Start the pod (UI, sync, bridge) and open the TUI
just aerc
```

Stop everything with `just aerc-down`.

## First run: log in to your Proton account

The bridge starts automatically on container launch, but on first run it has no
account and the bridge will exit waiting for interactive setup. Only **one**
bridge instance can run at a time, so stop the supervised one first, then open
the interactive CLI:

```bash
podman exec -it aerc-bridge /bin/bash

# inside the container:
pkill bridge
/app/bridge --cli
```

Inside the bridge interactive shell:

```text
>>> login
Username: your_account@proton.me
Password:
Two factor code:
Account your_account was added successfully.
```

If you use multiple addresses or custom domains, switch to split-address mode
so each address gets its own credentials (triggers another sync):

```text
>>> change mode 0
Are you sure you want to change the mode for account your_account to split? yes/no: yes
```

Now read the **generated** SMTP/IMAP credentials (not your Proton password) —

**copy these before exiting:**

```text
>>> info
Configuration for your_account@proton.me
IMAP Settings
Address:   127.0.0.1
IMAP port: 1143
Username:  your_account@proton.me
Password:  abcedfGHI12345

SMTP Settings
Address:   127.0.0.1
SMTP port: 1025
Username:  your_account@proton.me
Password:  abcedfGHI12345

>>> exit
```

Exit the container, then restart the bridge so it runs back under systemd
supervision:

```bash
exit
systemctl --user restart aerc-bridge.service
```

Verify the bridge is up on the pod's SMTP/IMAP sockets:

```bash
podman exec -it aerc-bridge /bin/bash -c 'netstat -ltpn'
# expect socat on 0.0.0.0:25 and 0.0.0.0:143
# and the bridge on 127.0.0.1:1025 and 127.0.0.1:1143
podman ps   # aerc-bridge should report (healthy)
```

## Wire the Proton account into aerc

Add Proton as an **additional** account. Any accounts that are not on Proton
are unchanged and keep connecting directly to their own servers.

`~/.config/aerc/accounts.conf`:

```ini
[Proton]
source = imap+ln://your_account@proton.me@127.0.0.1:143
outgoing = smtp+ln://your_account@proton.me@127.0.0.1:25
from = Your Name <your_account@proton.me>
```

`~/.config/isyncrc` (used by `aerc-sync`), e.g.:

```ini
IMAPAccount Proton
Host 127.0.0.1
Port 143
User your_account@proton.me
Pass <the password from `info`>

IMAPStore Proton-remote
Account Proton

MaildirStore Proton-local
Path ~/.local/share/mail/proton/
Inbox ~/.local/share/mail/proton/INBOX/

Channel Proton
Master :Proton-remote:
Slave :Proton-local:
Patterns INBOX
```

Notes:

* The bridge uses a self-signed certificate, so aerc/clients may warn about it
  — expected.
* The bridge requires a **paid** Proton plan (Mail Plus, Proton Unlimited, or
  Business); it will not work with a free account.
* Bridge state (config + encrypted credentials) persists in
  `~/.local/share/mail/:/root/` in the container.

## Updating the pinned bridge build

`BRIDGE_VERSION` in `apps/aerc/aerc.sh` and `ARG ENV_PROTONMAIL_BRIDGE_VERSION`
in `build/aerc-bridge/Containerfile` are pinned. To bump:

1. Check the latest release: `https://github.com/ProtonMail/proton-bridge/releases/latest`
2. Update both pins, then `just aerc-build` and restart the bridge.
