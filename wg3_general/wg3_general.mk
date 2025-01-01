#
# wg3_general_frontend - used for everything else not bt/usenet
#
# TODO
# Can't seem to get multiple networks connected to single VPN container
#
include wg3_general/.env

.PHONY: wg3-net-create
wg3-net-create:
	sudo docker network create --subnet=172.22.0.0/16 \
	--ipv6 --subnet fd22:1::/48 \
	wg3_general_frontend

.PHONY: wg3
wg3:
	sudo docker run -d \
		--name wg3 \
		--runtime=runc \
		--restart=unless-stopped \
		--memory=8g \
		--pids-limit=2048 \
		--security-opt=no-new-privileges \
		--cap-drop=all \
		--cap-add=NET_ADMIN \
		--sysctl net.ipv4.conf.all.src_valid_mark=1 \
		-p 18080:18080 \
		-p 18089:18089/tcp \
		-p 127.0.0.1:8558:8558 \
		-p 127.0.0.1:8337:8337 \
		-v ${c_data}/wireguard/${WG}.conf:/etc/wireguard/wg0.conf \
		-e ALLOWED_SUBNETS=${NETWORK}/24 \
		--network=wg3_general_frontend --ip=172.22.0.2 \
		ghcr.io/wfg/wireguard

.PHONY: wg3-run
wg3-run: wg3-net-create wg3

.PHONY: wg3-up
wg3-up:
	sudo docker compose --env-file global.env \
		--env-file wg3_general/.env \
		-f wg3_general/compose.yml \
		up -d

.PHONY: general_vpn-clean
general_vpn-clean:
	sudo docker stop wg3
	sudo docker network disconnect wg3_general_frontend traefik
	sudo docker network rm wg3_general_frontend
	sudo docker rm wg3
