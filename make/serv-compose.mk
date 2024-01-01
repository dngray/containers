#
# compose serv
#

compose-serv-build: compose-serv-build

compose-serv-up:
	sudo docker compose -f ./compose/vpn_general/compose.yml -p vpn_general up -d 
	sudo docker compose -f ./compose/beets/compose.yml -p beets up -d
	sudo docker compose -f ./compose/bitwarden/compose.yml -p bitwarden up -d
	sudo docker compose -f ./compose/flexo/compose.yml -p flexo up -d
	sudo docker compose -f ./compose/imapfilter/compose.yml -p imapfilter up -d
	sudo docker compose -f ./compose/powerwall/powerwall.yml -p powerwall up -d
	sudo docker compose -f ./compose/samba/compose.yml -p samba up -d
	sudo docker compose -f ./compose/simple-monerod/compose.yml -p simple-monerod up -d
	sudo docker compose -f ./compose/syncthing/compose.yml -p syncthing up -d
	sudo docker compose -f ./compose/traefik/compose.yml -p traefik up -d
	sudo docker compose -f ./compose/vault/compose.yml -p vault up -d
	sudo docker compose -f ./compose/terraforming-mars/compose.yml -p terraforming-mars up -d
	sudo docker compose -f ./compose/grocy/compose.yml -p grocy up -d
	sudo docker compose -f ./compose/changedetection/compose.yml -p changedetection up -d

compose-serv-down:
	sudo docker compose -f ./compose/vpn_general/compose.yml -p vpn_general down
	sudo docker compose -f ./compose/beets/compose.yml -p beets down
	sudo docker compose -f ./compose/bitwarden/compose.yml -p bitwarden down
	sudo docker compose -f ./compose/flexo/compose.yml -p flexo down
	sudo docker compose -f ./compose/imapfilter/compose.yml -p imapfilter down
	sudo docker compose -f ./compose/powerwall/powerwall.yml -p powerwall down
	sudo docker compose -f ./compose/samba/compose.yml -p samba down
	sudo docker compose -f ./compose/simple-monerod/compose.yml -p simple-monerod down
	sudo docker compose -f ./compose/syncthing/compose.yml -p syncthing down
	sudo docker compose -f ./compose/traefik/compose.yml -p traefik down
	sudo docker compose -f ./compose/vault/compose.yml -p vault down
	sudo docker compose -f ./compose/terraforming-mars/compose.yml -p terraforming-mars down
	sudo docker compose -f ./compose/terraforming-mars/compose.yml -p mars-postgres down
	sudo docker compose -f ./compose/grocy/compose.yml -p grocy down
	sudo docker compose -f ./compose/changedetection/compose.yml -p changedetection down

compose-serv-build:
	sudo docker compose -f ./compose/imapfilter/compose.yml -p imapfilter build
