MAKEFILE_DIR := $(dir $(lastword $(MAKEFILE_LIST)))
# Local podman/toolbx containers
include $(MAKEFILE_DIR)/aerc/aerc.mk
include $(MAKEFILE_DIR)/crowdin/crowdin.mk
include $(MAKEFILE_DIR)/pg/pg.mk
include $(MAKEFILE_DIR)/davmail/davmail.mk
include $(MAKEFILE_DIR)/dovecot/dovecot.mk
include $(MAKEFILE_DIR)/hugo/hugo.mk
include $(MAKEFILE_DIR)/imapfilter/imapfilter.mk
include $(MAKEFILE_DIR)/mailctl/mailctl.mk
include $(MAKEFILE_DIR)/pizauth/pizauth.mk
include $(MAKEFILE_DIR)/proton-bridge/proton-bridge.mk
include $(MAKEFILE_DIR)/toolbx/toolbx.mk
include $(MAKEFILE_DIR)/weechat/weechat.mk
# Gvisor containers
include $(MAKEFILE_DIR)/beets/beets.mk
include $(MAKEFILE_DIR)/busybox/busybox.mk
include $(MAKEFILE_DIR)/changedetection/changedetection.mk
include $(MAKEFILE_DIR)/flexo/flexo.mk
include $(MAKEFILE_DIR)/grafana/grafana.mk
include $(MAKEFILE_DIR)/grocy/grocy.mk
include $(MAKEFILE_DIR)/monero/monero.mk
include $(MAKEFILE_DIR)/mumble-server/mumble-server.mk
include $(MAKEFILE_DIR)/powerwall/powerwall.mk
include $(MAKEFILE_DIR)/smb/samba.mk
include $(MAKEFILE_DIR)/ssh/ssh.mk
include $(MAKEFILE_DIR)/syncthing/syncthing.mk
include $(MAKEFILE_DIR)/terraforming-mars/terraforming-mars.mk
include $(MAKEFILE_DIR)/traefik/traefik.mk
include $(MAKEFILE_DIR)/vault/vault.mk
include $(MAKEFILE_DIR)/vaultwarden/vaultwarden.mk
include $(MAKEFILE_DIR)/wg1_qbt/qbittorrent.mk
include $(MAKEFILE_DIR)/wg2_usenet/usenet.mk
include $(MAKEFILE_DIR)/wg3_general/wg3_general.mk
include $(MAKEFILE_DIR)/wg_test/wg_test.mk
include $(MAKEFILE_DIR)/whoami/whoami.mk

include global.env

SHELL=/bin/sh
UID := $(shell id -u)

list:
	sudo docker ps -all
	sudo docker images
	sudo docker network ls

.PHONY: all-stop
all-down:
	sudo docker stop $(sudo docker ps -aq)

.PHONY: all-remove
all-remove:
	sudo docker rm $(sudo docker ps -aq)

.PHONY: all-up
all-up: powerwall-run \
	grafana-run \
	vault-run \
	syncthing-run \
	bt-run \
	samba \
	flexo-run \
	wg2-up \
	wg3-up \
	vaultwarden-up \
	beets-up \
	traefik-run
