#
#  Usenet: Sabnzbd, Sonarr, Radarr, Lidar, Prowlarr
#
include wg2_usenet/.env

.PHONY: usenet-net-create
usenet-net-create:
	sudo docker network create --subnet=172.21.0.0/16 \
	--ipv6 --subnet fd21:1::/48 \
	wg2_usenet_frontend

.PHONY: usenet-vpn-create
usenet-vpn-create:
	sudo docker run -d \
		--name wg2 \
		--runtime=runc \
		--restart=unless-stopped \
		--memory=8g \
		--pids-limit=2048 \
		--security-opt=no-new-privileges \
		--cap-drop=all \
		--cap-add=NET_ADMIN \
		--sysctl net.ipv4.conf.all.src_valid_mark=1 \
		-p 127.0.0.1:6767:6767/tcp \
		-p 127.0.0.1:8989:8989/tcp \
		-p 127.0.0.1:7878:7878/tcp \
		-p 127.0.0.1:8686:8686/tcp \
		-p 127.0.0.1:9696:9696/tcp \
		-v ${c_data}/wireguard/${WG}.conf:/etc/wireguard/wg0.conf \
		-e ALLOWED_SUBNETS=${NETWORK}.0/24 \
		--network=wg2_usenet_frontend --ip=172.21.0.2 \
		ghcr.io/wfg/wireguard

.PHONY: sabnzbd
sabnzbd:
	sudo docker run -d \
		--name sabnzbd \
		--runtime=runsc-kvm \
		--restart=unless-stopped \
		--cpus=2 \
		--memory=4g \
		--pids-limit=1024 \
		--security-opt=no-new-privileges \
		--cap-drop=all \
		--cap-add=CHOWN \
		--cap-add=DAC_READ_SEARCH \
		--cap-add=SETGID \
		--cap-add=SETUID \
		-e PUID=1003 \
		-e PGID=1003 \
		-v ${c_data}/sabnzbd:/config \
		-v /mnt/shared/usenet/watch:/mnt/shared/usenet/watch \
		-v /mnt/shared/usenet/incoming:/mnt/shared/usenet/incoming \
		-v /mnt/shared/usenet/completed:/mnt/shared/usenet/completed \
		--network=container:wg2 \
		lscr.io/linuxserver/sabnzbd:latest

.PHONY: sonarr
sonarr:
	sudo docker run -d \
		--name sonarr \
		--runtime=runsc-kvm \
		--restart=unless-stopped \
		--cpus=2 \
		--memory=4g \
		--pids-limit=1024 \
		--security-opt=no-new-privileges \
		--cap-drop=all \
		--cap-add=CHOWN \
		--cap-add=DAC_READ_SEARCH \
		--cap-add=SETGID \
		--cap-add=SETUID \
		-e PUID=1003 \
		-e PGID=1003 \
		-v ${c_data}/sonarr:/config \
		-v /mnt/shared/tv:/mnt/shared/tv \
		-v /mnt/shared/usenet/watch:/mnt/shared/usenet/watch \
		-v /mnt/shared/usenet/incoming:/mnt/shared/usenet/incoming \
		-v /mnt/shared/usenet/completed:/mnt/shared/usenet/completed \
		--network=container:wg2 \
		lscr.io/linuxserver/sonarr:latest

.PHONY: radarr
radarr:
	sudo docker run -d \
		--name radarr \
		--runtime=runsc-kvm \
		--restart=unless-stopped \
		--cpus=2 \
		--memory=4g \
		--pids-limit=1024 \
		--security-opt=no-new-privileges \
		--cap-drop=all \
		--cap-add=CHOWN \
		--cap-add=DAC_READ_SEARCH \
		--cap-add=SETGID \
		--cap-add=SETUID \
		-e PUID=1003 \
		-e PGID=1003 \
		-v ${c_data}/radarr:/config \
		-v /mnt/shared/movies:/mnt/shared/movies \
		-v /mnt/shared/usenet/watch:/mnt/shared/usenet/watch \
		-v /mnt/shared/usenet/incoming:/mnt/shared/usenet/incoming \
		-v /mnt/shared/usenet/completed:/mnt/shared/usenet/completed \
		--network=container:wg2 \
		lscr.io/linuxserver/radarr:latest

.PHONY: lidarr
lidarr:
	sudo docker run \
		--name lidarr \
		--runtime=runsc-kvm \
		--restart=unless-stopped \
		--cpus=2 \
		--memory=4g \
		--pids-limit=1024 \
		--security-opt=no-new-privileges \
		--cap-drop=all \
		--cap-add=CHOWN \
		--cap-add=DAC_READ_SEARCH \
		--cap-add=SETGID \
		--cap-add=SETUID \
		-e PUID=1003 \
		-e PGID=1003 \
		-v ${c_data}/lidarr:/config \
		-v /mnt/shared/music:/mnt/shared/music \
		-v /mnt/shared/usenet/watch:/mnt/shared/usenet/watch \
		-v /mnt/shared/usenet/incoming:/mnt/shared/usenet/incoming \
		-v /mnt/shared/usenet/completed:/mnt/shared/usenet/completed \
		--network=container:wg2 \
		lscr.io/linuxserver/lidarr:latest

.PHONY: prowlarr
prowlarr:
	sudo docker run \
		--name prowlarr \
		--runtime=runsc-kvm \
		--restart=unless-stopped \
		--cpus=2 \
		--memory=4g \
		--pids-limit=1024 \
		--security-opt=no-new-privileges \
		--cap-drop=all \
		--cap-add=CHOWN \
		--cap-add=DAC_READ_SEARCH \
		--cap-add=SETGID \
		--cap-add=SETUID \
		-e PUID=1003 \
		-e PGID=1003 \
		-v ${c_data}/prowlarr:/config \
		--network=container:wg2 \
		lscr.io/linuxserver/prowlarr:latest

.PHONY: usenet-run
usenet-run: usenet-net-create \
	sabnzbd \
	sonarr \
	radarr \
	lidarr \
	prowlarr

.PHONY: wg2-up
wg2-up:
	sudo docker compose --env-file global.env \
		--env-file wg2_usenet/.env \
		-f wg2_usenet/compose.yml \
		up -d

.PHONY: usenet-clean
usenet-clean:
	sudo docker stop wg2 sabnzbd sonarr radarr lidarr prowlarr
	sudo docker network disconnect wg2_usenet_frontend traefik
	sudo docker network rm wg2_usenet_frontend
	sudo docker rm wg2 sabnzbd sonarr radarr lidarr prowlarr
