FEDORA_VERSION ?=  $(shell cat /etc/os-release | grep VERSION_ID | awk -F '=' '{ print $$2 }')
ARGS =

.PHONY: base
base:
	podman build $(ARGS) --pull=true --build-arg="fedora_version=$(FEDORA_VERSION)" -t base:$(FEDORA_VERSION) toolbx/f$(FEDORA_VERSION)/base/

.PHONY: mail
mail:
	podman build $(ARGS) --build-arg=fedora_version=$(FEDORA_VERSION) -t mail:$(FEDORA_VERSION) toolbx/f$(FEDORA_VERSION)/mail/

.PHONY: neovim
neovim:
	podman build $(ARGS) --build-arg=fedora_version=$(FEDORA_VERSION) -t neovim:$(FEDORA_VERSION) toolbx/f$(FEDORA_VERSION)/neovim/

.PHONY: mpv
mpv:
	podman build $(ARGS) --build-arg=fedora_version=$(FEDORA_VERSION) -t mpv:$(FEDORA_VERSION) toolbx/f$(FEDORA_VERSION)/mpv/

.PHONY: newsboat
newsboat:
	podman build $(ARGS) --build-arg=fedora_version=$(FEDORA_VERSION) -t newsboat:$(FEDORA_VERSION) toolbx/f$(FEDORA_VERSION)/newsboat/

.PHONY: tor-alpine
tor-alpine:
	podman-compose -f compose/podman/tor-alpine/container-compose.yml up -d

.PHONY: tor-socks-proxy
tor-socks-proxy:
	podman-compose -f compose/podman/tor-socks-proxy/container-compose.yml up -d
