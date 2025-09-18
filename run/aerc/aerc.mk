#
# Aerc
#

.PHONY: aerc-build
aerc-build:
	podman build -f build/aerc/Containerfile \
		--build-arg BUILD_DATE=$(date -u) \
		--build-arg UID=$(UID) \
		--build-arg LANG=en_US.UTF-8 \
		-t aerc:latest

.PHONY: aerc
aerc:
	podman run -it --replace --userns=keep-id \
		--hostname aerc \
		-v ~/.local/share/mail/:/home/aerc/.local/share/mail:z \
		-v ~/.config/aerc:/home/aerc/.config/aerc:z,ro \
		-v ~/.config/vdirsyncer/config:/home/aerc/.config/vdirsyncer/config:z,ro \
		-v ~/.config/email-common/:/home/aerc/.config/email-common:z,ro \
		-v ~/.config/nvim:/home/aerc/.config/nvim:z \
		-v ~/.config/goimapnotify/goimapnotify.yaml:/home/aerc/.config/goimapnotify/goimapnotify.yaml:z,ro \
		-v ~/.config/mailcap:/home/aerc/.config/mailcap:z,ro \
		-v ~/.local/share/nvim:/home/aerc/.local/share/nvim:z \
		-v ~/.local/share/address-book:/home/aerc/.local/share/address-book:z \
		-v ~/.local/share/calendars:/home/aerc/.local/share/calendars:z \
		-v ~/.local/state/nvim:/home/aerc/.local/state/nvim:z \
		-v ~/.local/state/vdirsyncer:/home/aerc/.local/state/vdirsyncer:z \
		-v ~/.gnupg:/home/aerc/.gnupg:z \
		-v ~/.config/khard:/home/aerc/.config/khard:z,ro \
		-v ~/.config/msmtp:/home/aerc/.config/msmtp:z,ro \
		-v ~/.config/notmuch:/home/aerc/.config/notmuch:z,ro \
		-v ~/.config/isyncrc:/home/aerc/.config/isyncrc:z,ro \
		-v ~/.local/state/isync:/home/aerc/.local/state/isync:z \
		-v ~/.config/gopass/:/home/aerc/.config/gopass/config:z,ro \
		-v ~/.local/share/gopass/:/home/aerc/.local/share/gopass:z \
		-v ~/.local/bin/msmtp-queue:/home/aerc/.local/bin/msmtp-queue:z,ro \
		-v ~/.local/bin/msmtpq:/home/aerc/.local/bin/msmtpq:z,ro \
		-v ~/.local/bin/sm:/home/aerc/.local/bin/sm:z,ro \
		-v ~/.config/mutt:/home/aerc/.config/mutt:z \
		-v ~/Downloads:/home/aerc/Downloads \
		-v /run/user/${UID}:/run/user/${UID}:ro \
		-e TZ="" \
		--security-opt label=type:container_t \
		--name aerc \
		localhost/aerc

.PHONY: aerc-clean
aerc-clean:
	podman rm -f localhost/aerc
	podman image rm localhost/aerc
