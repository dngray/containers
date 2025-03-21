#
# grocy
#

.PHONY: grocy
grocy:
	sudo docker run -d \
		--name grocy \
		--runtime=runsc-kvm \
		--restart=unless-stopped \
		--memory=8g \
		--pids-limit=2048 \
		--security-opt=no-new-privileges \
		--cap-drop=all \
		--cap-add=CHOWN \
		--cap-add=DAC_READ_SEARCH \
		--cap-add=SETGID \
		--cap-add=SETUID \
		-e PUID=1003 \
		-e PGID=1004 \
		--network=container:wg3 \
		-v ${c_data}/grocy:/config \
		lscr.io/linuxserver/grocy

grocy-run: grocy-network-create grocy-vpn-create grocy

.PHONY: grocy-clean
grocy-clean:
	sudo docker stop grocy
	sudo docker network rm grocy_frontend
	sudo docker rm grocy
