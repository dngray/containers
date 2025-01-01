#
# qbittorrent
#
include wg1_qbt/.env

.PHONY: bt-net-create
bt-net-create:
	sudo docker network create --subnet=172.20.0.0/16 \
	--ipv6 --subnet fd20:1::/48 \
	wg1_qbt_frontend

.PHONY: bt-vpn-create
bt-vpn-create:
	sudo docker run -d \
		--name wg1 \
		--runtime=runc \
		--restart=unless-stopped \
		--memory=8g \
		--pids-limit=2048 \
		--security-opt=no-new-privileges \
		--cap-drop=all \
		--cap-add=NET_ADMIN \
		--sysctl net.ipv4.conf.all.src_valid_mark=1 \
		-p 127.0.0.1:8081:8081/tcp \
		-v ${c_data}/wireguard/${WG}.conf:/etc/wireguard/wg0.conf \
		-e ALLOWED_SUBNETS=${NETWORK}.0/24 \
		--network=wg1_qbt_frontend --ip=172.20.0.2 \
		ghcr.io/wfg/wireguard

.PHONY: qbittorrent
qbittorrent:
	sudo docker run -d \
		--name qbittorrent \
		--runtime=runsc-kvm \
		--restart=unless-stopped \
		--cpus=4 \
		--memory=14g \
		--pids-limit=2048 \
		--security-opt=no-new-privileges \
		--cap-drop=ALL \
		--cap-add=CHOWN \
		--cap-add=DAC_READ_SEARCH \
		--cap-add=SETGID \
		--cap-add=SETUID \
		-e PUID=1003 \
		-e PGID=1003 \
		-e WEBUI_PORT=8081 \
		-v ${c_data}/qbittorrent:/config \
		-v /mnt/shared/incoming:/mnt/shared/incoming \
		-v /mnt/shared/movies:/mnt/shared/movies \
		-v /mnt/shared/tv:/mnt/shared/tv \
		--network=container:wg1 \
		lscr.io/linuxserver/qbittorrent

bt-run: bt-net-create bt-vpn-create qbittorrent

.PHONY: bt-clean
bt-clean:
	sudo docker stop wg1 qbittorrent
	sudo docker network disconnect wg1_qbt_frontend traefik
	sudo docker network rm wg1_qbt_frontend
	sudo docker rm wg1 qbittorrent
