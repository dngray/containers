#
# pizauth
#

DATE := $(shell date '+%Y-%m-%d-%H:%M:%S')
.PHONY: pizauth-build
pizauth-build:
	podman build -f pizauth/Containerfile \
		--build-arg BUILD_DATE=${DATE} \
		--build-arg IMAGE_VERSION=1.0.4 \
		-t pizauth:latest

.PHONY: pizauth
pizauth:
	podman run --replace --userns=keep-id \
		-v ~/.config/pizauth.conf:/home/pizauth/.config/pizauth.conf:z,ro \
		-p 8080:8080 \
		--name pizauth \
		localhost/pizauth tail -f /dev/null

.PHONY: pizauth-clean
pizauth-clean:
	podman rm -f localhost/pizauth
	podman image rm localhost/pizauth
