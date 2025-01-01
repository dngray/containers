#
# Traefik
#

.PHONY: traefik-build
traefik-build:
	sudo docker build . -f traefik/build/Dockerfile \
		-t localhost/traefik

.PHONY: traefik
traefik:
	sudo docker run -d \
		--name traefik \
		--runtime=runsc-kvm \
		--restart=unless-stopped \
		--read-only \
		--memory=8g \
		--pids-limit=2048 \
		--security-opt=no-new-privileges \
		--cap-drop=all \
		--user=1003:1003 \
		-p 8675:8675 \
		-p 80:8080 \
		-p 443:4430 \
		-p 443:4430/udp \
		--label=traefik.enable=true \
		--label=traefik.docker.network=http_network \
		-e LEGO_CA_CERTIFICATES='/etc/traefik/certs/root.crt' \
		-v ${PWD}/traefik/data/traefik.yml:/etc/traefik/traefik.yml \
		-v ${PWD}/traefik/data/conf.d:/etc/traefik/conf.d \
		-v ${c_data}/traefik/acme.json:/etc/acme/acme.json \
		-v ${c_data}/traefik/certs:/etc/traefik/certs:ro \
		--env-file=${PWD}/traefik/data/traefik.env \
		localhost/traefik
		#docker.io/traefik:latest

.PHONY: traefik-net-connect
traefik-net-connect:
	sudo docker network connect pypowerwall_backend traefik
	sudo docker network connect grafana_frontend traefik
	sudo docker network connect vault_frontend traefik
	sudo docker network connect syncthing1_frontend traefik
	sudo docker network connect syncthing2_frontend traefik
	sudo docker network connect flexo_frontend traefik
	sudo docker network connect wg1_qbt_frontend traefik
	sudo docker network connect wg2_usenet_frontend traefik
	sudo docker network connect wg3_general_frontend traefik

.PHONY: traefik-run
traefik-run: traefik \
	traefik-net-connect

.PHONY: traefik-up
traefik-up:
	sudo docker compose --env-file global.env \
		-f traefik/compose.yml \
		up

.PHONY: traefik-clean
traefik-clean:
	sudo docker stop traefik
	sudo docker rm traefik
