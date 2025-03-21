#
# Weechat
#

DATE := $(shell date '+%Y-%m-%d-%H:%M:%S')
.PHONY: tor-router-build
tor-router-build:
	sudo podman build -f build/tor-router/src/Dockerfile \
		--build-arg "BUILD_DATE=${DATE}" \
		-t localhost/tor-router \

.PHONY: tor-network-create
tor-network-create:
	sudo podman network create --internal tor

.PHONY: tor-router-run
tor-router-run:
	sudo podman run --replace \
		--name=tor-router \
		--cap-add=NET_ADMIN \
		--dns=127.0.0.1 \
		-p 9050:9050 \
		--restart=unless-stopped \
		localhost/tor-router

.PHONY: weechat
weechat:
	podman run -it --replace --userns=keep-id \
		--name weechat \
		--user=1000 \
		-v ~/.config/weechat:/home/user/.config/weechat \
		-v ~/.local/share/weechat:/home/user/.local/share/weechat \
		-v ~/.cache/weechat:/home/user/.cache/weechat \
		docker.io/weechat/weechat:latest-alpine

.PHONY: weechat-run
weechat-run: tor-router-build tor-route-run weechat

.PHONY: weechat-clean
weechat-clean:
	sudo podman stop tor-router weechat
	sudo podman rm -f tor-router weechat
	sudo podman image rm tor-router weechat
	sudo podman network rm tor
	podman stop tor-router weechat
	podman rm -f tor-router weechat
	podman image rm tor-router weechat
