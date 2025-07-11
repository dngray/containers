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
	sudo ${CMD} compose --env-file compose/.env -f compose/traefik/compose.yml build

.PHONY: stepca
stepca:
	sudo ${CMD} compose --env-file compose/.env -f compose/stepca/compose.yml up -d

.PHONY: all-up
all-up: stepca
	sudo ${CMD} compose --env-file compose/.env -f compose/wg1_qbt/compose.yml up -d
	sudo ${CMD} compose --env-file compose/.env -f compose/wg2_usenet/compose.yml up -d
	sudo ${CMD} compose --env-file compose/.env -f compose/wg3_general/compose.yml up -d
	sudo ${CMD} compose --env-file compose/.env -f compose/beets/compose.yml up -d
	sudo ${CMD} compose --env-file compose/.env -f compose/vaultwarden/compose.yml up -d
	sudo ${CMD} compose --env-file compose/.env -f compose/vault/compose.yml up -d
	sudo ${CMD} compose --env-file compose/.env -f compose/syncthing/compose.yml up -d
	sudo ${CMD} compose --env-file compose/.env -f compose/smb/compose.yml up -d
	sudo ${CMD} compose --env-file compose/.env -f compose/flexo/compose.yml up -d
	sudo ${CMD} compose --env-file compose/.env --env-file compose/powerwall/.env -f compose/powerwall/compose.yml up -d
	sudo ${CMD} compose --env-file compose/.env -f compose/grafana/compose.yml up -d
	sudo ${CMD} compose --env-file compose/.env -f compose/cinny/compose.yml up -d
	sudo ${CMD} compose --env-file compose/.env -f compose/traefik/compose.yml up -d
