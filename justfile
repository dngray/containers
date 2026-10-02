# Container management toolkit
# Run `just --list` for the grouped command reference.

set shell := ["/bin/sh", "-eu", "-c"]

# Show the grouped command list
default:
    @just --list

# Bring up all compose files
[group('docker')]
docker-all-up:
    ./compose/manage-compose.sh all-up

# Rebuild and bring up all compose files
[group('docker')]
docker-up-build:
    ./compose/manage-compose.sh up-build

# Rebuild Traefik edge proxy
[group('docker')]
docker-traefik-build:
    ./compose/manage-compose.sh traefik-build

# Rebuild Tang NBDE server
[group('docker')]
docker-tang-build:
    ./compose/manage-compose.sh tang-build

# Rebuild music stack (mpd, snapcast, cyp)
[group('docker')]
docker-music-build:
    ./compose/manage-compose.sh music-build

# Show all running containers, images, and networks
[group('docker')]
docker-list:
    ./compose/manage-compose.sh list

# Stop every container on the VM
[group('docker')]
docker-all-down:
    ./compose/manage-compose.sh stop-all

# Remove all container instances from storage
[group('docker')]
docker-all-remove:
    ./compose/manage-compose.sh rm-all

# Flush all cached Docker image layers
[group('docker')]
docker-images-flush:
    ./compose/manage-compose.sh rmi-all

# Remove stopped containers and prune unused networks
[group('docker')]
docker-prune-net:
    ./compose/manage-compose.sh prune-net

# Compile Go-template configurations using global gomplate schema
[group('docker')]
template:
    podman run -v ./:/data:Z -v ./:/input:Z -v ./:/output:Z docker.io/hairyhenderson/gomplate --config=/input/.gomplate.yaml -V

# Delete generated configs listed in .gomplate.yaml outputFiles
[group('docker')]
clean:
    ./bin/gomplate-clean

# Open mail client cluster pod (UI, sync, Proton bridge)
[group('podman')]
aerc:
    ./apps/aerc/aerc.sh start

# Tear down and stop the entire mail pod service mesh
[group('podman')]
aerc-down:
    ./apps/aerc/aerc.sh stop

# Build split Aerc UI, Mail-Sync, and Proton Bridge images
[group('podman')]
aerc-build:
    ./apps/aerc/aerc.sh build

# Remove Aerc system images and container structures
[group('podman')]
aerc-clean:
    ./apps/aerc/aerc.sh clean

# Push Aerc UI, Mail-Sync, and Proton Bridge images to container registry
[group('podman')]
aerc-publish:
    ./apps/aerc/aerc.sh publish

# Build split Aerc SELinux policy module (.cil)
[group('selinux')]
aerc-selinux-cil:
    ./bin/build-selinux selinux-aerc apps/aerc build/aerc
    @echo "Next steps for live testing:"
    @echo "  sudo semodule -r container_aerc 2>/dev/null || true   # only on the first rename"
    @echo "  sudo semodule -i {{justfile_directory()}}/build/aerc/selinux-aerc.cil"
    @echo "  sudo restorecon -RFv $HOME/.config/aerc"

# Build split Aerc SELinux policy RPM package
[group('selinux')]
aerc-selinux-rpm: aerc-selinux-cil
    ./bin/create-rpm apps/aerc/selinux-aerc.spec build/aerc/rpm build/aerc/selinux-aerc.cil

# Run translation tool interactive shell
[group('podman')]
crowdin:
    ./apps/crowdin/crowdin.sh run

# Pull translations
[group('podman')]
crowdin-pull:
    ./apps/crowdin/crowdin.sh pull

# Clean translation artifacts
[group('podman')]
crowdin-clean:
    ./apps/crowdin/crowdin.sh clean

# Start Exchange mail gateway proxy
[group('podman')]
davmail:
    ./apps/davmail/davmail.sh run

# Build Davmail container
[group('podman')]
davmail-build:
    ./apps/davmail/davmail.sh build

# Remove Davmail container and image
[group('podman')]
davmail-clean:
    ./apps/davmail/davmail.sh clean

# Run imapfilter sorting script
[group('podman')]
imapfilter:
    ./apps/imapfilter/imapfilter.sh run

# Build Imapfilter container
[group('podman')]
imapfilter-build:
    ./apps/imapfilter/imapfilter.sh build

# Remove Imapfilter container and image
[group('podman')]
imapfilter-clean:
    ./apps/imapfilter/imapfilter.sh clean

# Build Neovim deb package from source
[group('podman')]
neovim-build:
    ./bin/debian-build-neovim build

# Remove Neovim build artifacts
[group('podman')]
neovim-build-clean:
    ./bin/debian-build-neovim clean

# Execute synchronous Tree-sitter compilation cascade
[group('podman')]
neovim-parsers-update:
    ./apps/neovim/treesitter.sh update

# Build custom micro-compiler image for Treesitter
[group('podman')]
neovim-parsers-build:
    ./apps/neovim/treesitter.sh build

# Remove Treesitter compiler image layers
[group('podman')]
neovim-parsers-clean:
    ./apps/neovim/treesitter.sh clean

# Build Snapcast client container for laptop playback
[group('podman')]
snapclient-build:
    ./apps/snapclient/snapclient.sh build

# Remove Snapcast client image
[group('podman')]
snapclient-clean:
    ./apps/snapclient/snapclient.sh clean

# Push Snapclient image to container registry
[group('podman')]
snapclient-publish:
    ./apps/snapclient/snapclient.sh publish

# Build snapclient SELinux policy module (.cil)
[group('selinux')]
snapclient-selinux-cil:
    ./bin/build-selinux selinux-snapclient apps/snapclient build/snapclient
    @echo "Next steps for live testing:"
    @echo "  sudo semodule -r container_snapclient 2>/dev/null || true   # only on the first rename"
    @echo "  sudo semodule -i {{justfile_directory()}}/build/snapclient/selinux-snapclient.cil"

# Build snapclient SELinux policy RPM package
[group('selinux')]
snapclient-selinux-rpm: snapclient-selinux-cil
    ./bin/create-rpm apps/snapclient/selinux-snapclient.spec build/snapclient/rpm build/snapclient/selinux-snapclient.cil

# Start local TFTP daemon (rootful) on port 69/udp
[group('podman')]
tftp:
    ./apps/tftp/tftp.sh run

# Compile local tftpd-hpa execution image via Podman
[group('podman')]
tftp-build:
    ./apps/tftp/tftp.sh build

# Force purge local tftp storage container and engine image
[group('podman')]
tftp-clean:
    ./apps/tftp/tftp.sh clean

# Build cold cache layer catalog for Opencode via buildah
[group('agents')]
opencode-layers:
    ./apps/opencode/opencode.sh layers

# Assemble backend server image from composed buildah layers
[group('agents')]
opencode-server:
    ./apps/opencode/opencode.sh server

# Assemble slim TUI client image from the opencode binary layer
[group('agents')]
opencode-tui:
    ./apps/opencode/opencode.sh tui

# Push Opencode server/TUI images (`full`=src+py/pg/rust, `full-binary`, `basic`, `basic-binary`)
[group('agents')]
opencode-publish variant="":
    ./apps/opencode/opencode.sh publish {{variant}}

# Remove Opencode agent jails and container imagery
[group('agents')]
opencode-clean:
    ./apps/opencode/opencode.sh clean

# Build centralized Goose AI Server
[group('agents')]
goose-server:
    ./apps/goose/goose.sh server

# Build interactive terminal Goose CLI
[group('agents')]
goose-cli:
    ./apps/goose/goose.sh cli

# Push Goose server and CLI images to container registry
[group('agents')]
goose-publish:
    ./apps/goose/goose.sh publish

# Remove Goose agent jails and container imagery
[group('agents')]
goose-clean:
    ./apps/goose/goose.sh clean

# Build fortress SELinux policy module (.cil) for an API generation (v1|v2)
[group('selinux')]
fortress-selinux-cil version="v1":
    ./bin/build-selinux selinux-fortress apps/fortress/selinux/{{version}} apps/fortress/selinux/{{version}}
    @echo "Next steps for live testing ({{version}}):"
    @echo "  sudo semodule -r ai_fortress 2>/dev/null || true   # only on the first rename"
    @echo "  sudo semodule -i {{justfile_directory()}}/apps/fortress/selinux/{{version}}/selinux-fortress.cil"
    @echo "  sudo restorecon -RFv $HOME/.config/fortress $HOME/.cache/fortress $HOME/.local/share/fortress $HOME/.local/state/fortress $HOME/src $HOME/workspace"

# Build fortress SELinux policy RPM package for an API generation (v1|v2)
[group('selinux')]
fortress-selinux-rpm version="v1": (fortress-selinux-cil version)
    ./bin/create-rpm apps/fortress/selinux/{{version}}/selinux-fortress.spec apps/fortress/selinux/{{version}}/rpm apps/fortress/selinux/{{version}}/selinux-fortress.cil

# Verify a policy regenerates byte-identically (needs selinux-policy-devel)
[group('selinux')]
fortress-selinux-verify version="v1":
    @if [ ! -f apps/fortress/selinux/{{version}}/selinux-fortress.cil ]; then \
      echo "no pre-existing .cil to compare against -- run 'just fortress-selinux-cil {{version}}' once first"; \
      exit 1; \
    fi
    cp apps/fortress/selinux/{{version}}/selinux-fortress.cil apps/fortress/selinux/{{version}}/selinux-fortress.cil.orig
    just fortress-selinux-cil {{version}}
    @if diff -u apps/fortress/selinux/{{version}}/selinux-fortress.cil.orig apps/fortress/selinux/{{version}}/selinux-fortress.cil; then \
      echo "OK: {{version}} policy regenerated byte-identically"; \
      rm -f apps/fortress/selinux/{{version}}/selinux-fortress.cil.orig; \
    else \
      echo "DRIFT: {{version}} policy changed; the .orig file is kept for inspection"; \
      exit 1; \
    fi

# Report where the v1 and v2 policy inputs have diverged (informational)
[group('selinux')]
fortress-selinux-diff:
    @for f in selinux-fortress.te selinux-fortress.fc selinux-fortress.spec; do \
      if cmp -s apps/fortress/selinux/v1/$f apps/fortress/selinux/v2/$f; then \
        echo "  same      $f"; \
      else \
        echo "  DIVERGED  $f"; diff -u apps/fortress/selinux/v1/$f apps/fortress/selinux/v2/$f || true; \
      fi; \
    done
    @if cmp -s apps/fortress/selinux/v1/selinux-fortress.ports apps/fortress/selinux/v2/selinux-fortress.ports; then \
      echo "  same      selinux-fortress.ports"; \
    else \
      echo "  expected  selinux-fortress.ports differs (that is the API port):"; \
      diff -u apps/fortress/selinux/v1/selinux-fortress.ports apps/fortress/selinux/v2/selinux-fortress.ports || true; \
    fi

# Print the resolved seat plan without launching anything
[group('agents')]
fortress-plan agent="opencode" role="server" variant="latest" api="v2":
    FORTRESS_PATH="{{justfile_directory()}}" OPENCODE_VARIANT="{{variant}}" OPENCODE_API="{{api}}" \
      ./apps/fortress/fortress-exec {{agent}} {{role}} --print-plan

# Run the Fortress regression tests
[group('agents')]
fortress-test:
    ./tests/run-tests.sh
