#
# beets
#

.PHONY: beets
beets:
	sudo docker run -d \
		--name beets \
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
		-e PGID=1004 \
		--network=container:wg3 \
		-v ${c_data}/beets:/config \
		-v /mnt/shared/music:/music \
		-v /mnt/shared/usenet/completed:/downloads \
		lscr.io/linuxserver/beets

.PHONY: beets-up
beets-up:
	sudo docker compose --env-file global.env \
		-f beets/compose.yml \
		up -d

.PHONY: beets-clean
beets-clean:
	sudo docker stop beets
	sudo docker network rm beets_frontend
	sudo docker rm beets
