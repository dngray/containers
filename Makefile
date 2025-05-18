MAKEFILE_DIR := $(dir $(lastword $(MAKEFILE_LIST)))
include $(MAKEFILE_DIR)/make/arr.mk
include $(MAKEFILE_DIR)/make/serv.mk
include $(MAKEFILE_DIR)/make/arr-compose.mk
include $(MAKEFILE_DIR)/make/serv-compose.mk
include $(MAKEFILE_DIR)/make/aerc.mk
include $(MAKEFILE_DIR)/make/imapfilter.mk

SHELL=/bin/sh
UID := $(shell id -u)

list:
	docker ps -all
	docker images
	docker network ls

template:
	podman run -v ./:/data:Z \
		-v ./:/input:Z \
		-v ./:/output:Z \
		docker.io/hairyhenderson/gomplate \
		--config=/input/.gomplate.yaml -V

network: 
	sudo docker network create --subnet=172.18.0.0/16 \
		-d bridge \
		-o com.docker.network.bridge.name=traefik-proxy \
		traefik-proxy

all-build: compose-serv-build

all-clean: all-arr-clean all-serv-clean
	sudo docker system prune -f
	sudo docker ps -all
	sudo docker images

all-up: compose-arr-up compose-serv-up

all-down: compose-arr-down compose-serv-down

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

.PHONY: tor-alpine
tor-alpine:
	podman-compose -f compose/podman/tor-alpine/container-compose.yml up -d

.PHONY: tor-socks-proxy
tor-socks-proxy:
	podman-compose -f compose/podman/tor-socks-proxy/container-compose.yml up -d
