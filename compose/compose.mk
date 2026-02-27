.PHONY: build
build:
	sudo ${CMD} compose --env-file compose/.env -f compose/traefik/compose.yml build

.PHONY: stepca
stepca:
	sudo ${CMD} compose --env-file compose/.env -f compose/stepca/compose.yml up -d

.PHONY: registry
registry:
	sudo ${CMD} compose --env-file compose/.env -f compose/registry/compose.yml up -d

.PHONY: harbor
harbor:
	sudo ${CMD} compose --env-file compose/.env -f compose/harbor/compose.yml up -d

.PHONY: mumble
mumble:
	sudo ${CMD} compose --env-file compose/.env -f compose/mumble/compose.yml up -d

.PHONY: all-up
all-up: stepca harbor mumble
	sudo ${CMD} compose --env-file compose/.env -f compose/wg1_qbt/compose.yml up -d
	sudo ${CMD} compose --env-file compose/.env -f compose/wg2_usenet/compose.yml up -d
	sudo ${CMD} compose --env-file compose/.env -f compose/wg3_general/compose.yml up -d
	sudo ${CMD} compose --env-file compose/.env -f compose/beets/compose.yml up -d
	sudo ${CMD} compose --env-file compose/.env -f compose/navidrome/compose.yml up -d
	sudo ${CMD} compose --env-file compose/.env -f compose/vaultwarden/compose.yml up -d
	sudo ${CMD} compose --env-file compose/.env -f compose/vault/compose.yml up -d
	sudo ${CMD} compose --env-file compose/.env -f compose/syncthing/compose.yml up -d
	sudo ${CMD} compose --env-file compose/.env -f compose/smb/compose.yml up -d
	sudo ${CMD} compose --env-file compose/.env -f compose/flexo/compose.yml up -d
	sudo ${CMD} compose --env-file compose/.env --env-file compose/powerwall/.env \
		-f compose/powerwall/compose.yml up -d
	sudo ${CMD} compose --env-file compose/.env -f compose/grafana/compose.yml up -d
	sudo ${CMD} compose --env-file compose/.env -f compose/cinny/compose.yml up -d
	sudo ${CMD} compose --env-file compose/.env -f compose/traefik/compose.yml up -d
