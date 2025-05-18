#
# compose arr
#

compose-arr-build:

compose-arr-up:
	sudo docker compose -f ./compose/qbittorrent/compose.yml -p qbittorrent up -d
	sudo docker compose -f ./compose/usenet/compose.yml -p usenet up -d

compose-arr-down:
	sudo docker compose -f ./compose/qbittorrent/compose.yml -p qbittorrent down
	sudo docker compose -f ./compose/usenet/compose.yml -p usenet down

compose-arr-clean:
	sudo docker rm -f vpn_bittorrent
	sudo docker rm -f vpn_usenet
	sudo docker rmi -f vpn_bittorrent
	sudo docker rmi -f vpn_usenet
