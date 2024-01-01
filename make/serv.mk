#
# server
#

all-serv-build: serv-build

all-serv-clean: all-serv-containers-clean all-serv-images-clean

serv-build:
	sudo docker build -f ./build/imapfilter/Dockerfile \
		-t imapfilter:latest \
		.

all-serv-containers-clean:
	sudo docker rm -f beets
	sudo docker rm -f vaultwarden
	sudo docker rm -f vw_backup
	sudo docker rm -f flexo
	sudo docker rm -f imapfilter
	sudo docker rm -f grafana
	sudo docker rm -f influxdb
	sudo docker rm -f pypowerwall
	sudo docker rm -f telegraf
	sudo docker rm -f weather411
	sudo docker rm -f monerod
	sudo docker rm -f watchtower
	sudo docker rm -f samba
	sudo docker rm -f syncthingb
	sudo docker rm -f syncthingd
	sudo docker rm -f traefik
	sudo docker rm -f vault
	sudo docker rm -f vpn_general
	sudo docker rm -f terraforming-mars
	sudo docker rm -f mars-postgres
	sudo docker rm -f grocy
	sudo docker rm -f changedetection

all-serv-images-clean:
	sudo docker rmi -f lscr.io/linuxserver/beets
	sudo docker rmi -f vaultwarden/server
	sudo docker rmi -f bruceforce/vaultwarden-backup
	sudo docker rmi -f nroi/flexo
	sudo docker rmi -f imapfilter
	sudo docker rmi -f grafana/grafana:9.1.2-ubuntu
	sudo docker rmi -f influxdb:1.8
	sudo docker rmi -f jasonacox/pypowerwall
	sudo docker rmi -f telegraf:latest
	sudo docker rmi -f jasonacox/weather411
	sudo docker rmi -f containrrr/watchtower
	sudo docker rmi -f sethsimmons/simple-monerod
	sudo docker rmi -f crazymax/samba
	sudo docker rmi -f ghcr.io/linuxserver/syncthing
	sudo docker rmi -f traefik
	sudo docker rmi -f vault
	sudo docker rmi -f ghcr.io/wfg/openvpn-client
	sudo docker rmi -f andrewsav/terraforming-mars
	sudo docker rmi -f postgres
	sudo docker rmi -f grocy
	sudo docker rmi -f changedetection
