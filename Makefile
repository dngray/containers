SHELL=/bin/sh
UID := $(shell id -u)
CMD := docker

list:
	sudo ${CMD} ps -all
	sudo ${CMD} images
	sudo ${CMD} network ls

.PHONY: all-down
all-down:
	sudo ${CMD} stop $$(sudo docker ps -aq)

.PHONY: all-remove
all-remove:
	sudo ${CMD} rm $$(sudo docker ps -aq)
	sudo ${CMD} network prune

.PHONY: build
build:
	sudo ${CMD} compose -f compose/traefik/compose.yml build

.PHONY: all-up
all-up:
	sudo ${CMD} compose -f compose/wg1_qbt/compose.yml up -d
	sudo ${CMD} compose -f compose/wg2_usenet/compose.yml up -d
	sudo ${CMD} compose -f compose/wg3_general/compose.yml up -d
	sudo ${CMD} compose -f compose/beets/compose.yml up -d
	sudo ${CMD} compose -f compose/vaultwarden/compose.yml up -d
	sudo ${CMD} compose -f compose/vault/compose.yml up -d
	sudo ${CMD} compose -f compose/syncthing/compose.yml up -d
	sudo ${CMD} compose -f compose/smb/compose.yml up -d
	sudo ${CMD} compose -f compose/flexo/compose.yml up -d
	sudo ${CMD} compose -f compose/powerwall/compose.yml up -d
	sudo ${CMD} compose -f compose/grafana/compose.yml up -d
	sudo ${CMD} compose -f compose/traefik/compose.yml up -d
