#
# Aerc container targets
#

# Read-write mounts (local/share, local/state, Downloads, .gnupg)
RW_MOUNTS := \
	.local/share/mail \
	.local/share/nvim \
	.local/share/address-book \
	.local/share/calendars \
	.local/state/vdirsyncer \
	.local/state/isync \
	.local/share/gopass \
	.gnupg \
	Downloads

# Read-only mounts (everything in .config + local/bin)
RO_MOUNTS := \
	.local/bin/msmtp-queue \
	.local/bin/msmtpq \
	.local/bin/sm \
	.config/aerc \
	.config/vdirsyncer/config \
	.config/email-common \
	.config/nvim \
	.config/goimapnotify/goimapnotify.yaml \
	.config/mailcap \
	.config/khard \
	.config/msmtp \
	.config/notmuch \
	.config/isyncrc \
	.config/gopass/config \
	.config/mutt

.PHONY: aerc-build
aerc-build:
	@echo "Building Aerc container..."
	podman build -f build/aerc/Containerfile \
		--build-arg LANG=en_US.UTF-8 \
		--build-arg HOST_UID=${UID} \
		--build-arg HOST_GID=${GID} \
		-t aerc:latest

aerc:
	@echo "Starting Aerc container..."
	@podman run -it --replace \
		--userns=keep-id \
		-u ${UID}:${GID} \
		--hostname aerc \
		--name aerc \
		--security-opt label=type:container_t \
		-e TZ="" \
		$(foreach m,$(RW_MOUNTS),--mount type=bind,source=$(HOME)/$(m),target=/home/aerc/$(m) ) \
		$(foreach m,$(RO_MOUNTS),--mount type=bind,source=$(HOME)/$(m),target=/home/aerc/$(m),readonly ) \
		--mount type=bind,source=/run/user/${UID},target=/run/user/${UID},readonly \
		localhost/aerc

.PHONY: aerc-clean
aerc-clean:
	@echo "Cleaning Aerc container..."
	podman rm -f aerc || true
	podman image rm aerc || true
