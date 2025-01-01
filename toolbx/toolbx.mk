#FEDORA_VERSION ?=  $(shell cat /etc/os-release | grep VERSION_ID | awk -F '=' '{ print $$2 }')
FEDORA_VERSION ?= 39
ARGS =

.PHONY: base
base:
	podman build $(ARGS) \
	--pull=true \
	--build-arg="fedora_version=$(FEDORA_VERSION)" -t base:$(FEDORA_VERSION) toolbx/f$(FEDORA_VERSION)/base/

.PHONY: mpv
mpv:
	podman build $(ARGS) --build-arg=fedora_version=$(FEDORA_VERSION) -t mpv:$(FEDORA_VERSION) toolbx/f$(FEDORA_VERSION)/mpv/

.PHONY: newsboat
newsboat:
	podman build $(ARGS) --build-arg=fedora_version=$(FEDORA_VERSION) -t newsboat:$(FEDORA_VERSION) toolbx/f$(FEDORA_VERSION)/newsboat/
