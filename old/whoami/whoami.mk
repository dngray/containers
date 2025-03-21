#
# whoami
#

.PHONY: whoami-network-create
whoami-network-create:
	sudo podman network create --subnet=172.18.0.0/16 \
	--ipv6 --subnet fcdd:1::/48 \
	whoami_frontend

.PHONY: whoami
whoami:
	sudo podman run \
		--name whoami \
		--runtime=runsc \
		--runtime-flag platform=kvm \
		--runtime-flag network=host \
		--restart=unless-stopped \
		--read-only \
		--memory=8g \
		--pids-limit=2048 \
		--security-opt=no-new-privileges \
		--cap-drop=all \
		--user=1300:1300 \
		-e WHOAMI_PORT_NUMBER='9999' \
		-e ${NETWORK} \
		--network=whoami_frontend --ip=172.18.0.2 \
		docker.io/traefik/whoami

whoami-run: whoami-network-create whoami

.PHONY: whoami-clean
whoami-clean:
	sudo podman stop whoami
	sudo podman network rm whoami_frontend
	sudo podman rm whoami
