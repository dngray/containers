#
# busybox
#

.PHONY: busybox-net-create
busybox-net-create:
	sudo docker network create --subnet=172.19.0.0/16 \
	--ipv6 --subnet fd19:1::/48 \
	busybox_frontend

.PHONY: busybox-vpn-create
busybox-vpn-create:
	sudo docker run \
		--name busybox_vpn \
		--runtime=runc \
		--restart=unless-stopped \
		--memory=8g \
		--pids-limit=2048 \
		--security-opt=no-new-privileges \
		--cap-drop=all \
		--cap-add=NET_ADMIN \
		--sysctl net.ipv4.conf.all.src_valid_mark=1 \
		-p 8123:8123/tcp \
		-v ${c_data}/wireguard/${WG}.conf:/etc/wireguard/wg0.conf \
		--network=busybox_frontend --ip=172.19.0.2 \
		-e ALLOWED_SUBNETS=${NETWORK}.0/24 \
		ghcr.io/wfg/wireguard

.PHONY: busybox
busybox:
	sudo docker run -it \
		--name busybox \
		--runtime=runsc-kvm \
		--restart=unless-stopped \
		--memory=8g \
		--pids-limit=2048 \
		--security-opt=no-new-privileges \
		--cap-drop=all \
		--user=1400:1400 \
		--network=container:busybox_vpn \
		docker.io/busybox \
		httpd -f -p 8123 -h /etc/

.PHONY: busybox-run
busybox-run: busybox-net-create busybox-vpn-create busybox

.PHONY: busybox-clean
busybox-clean:
	sudo docker stop busybox_vpn busybox
	sudo docker network rm busybox_frontend
	sudo docker rm busybox_vpn busybox
