#
# vaultwarden
#

.PHONY: vaultwarden
vaultwarden:
	sudo docker run -d \
		--name vaultwarden \
		--runtime=runsc-kvm \
		--restart=unless-stopped \
		--cpus=2 \
		--memory=4g \
		--pids-limit=512 \
		--security-opt=no-new-privileges \
		--cap-drop=all \
		--cap-add=CHOWN \
		--user=1003:1003 \
		-e WEBSOCKET_ENABLED=true \
		-e WEB_VAULT_ENABLED=true \
		-e ADMIN_TOKEN=${ADMIN_TOKEN} \
		-e ROCKET_PORT=8558 \
		-v ${c_data}/vaultwarden:/data \
		--network=container:wg3 \
		docker.io/vaultwarden/server:latest

.PHONY: vaultwarden-up
vaultwarden-up:
	sudo docker compose --env-file global.env \
		--env-file vaultwarden/.env \
		-f vaultwarden/compose.yml \
		up -d

.PHONY: vaultwarden-clean
vaultwarden-clean:
	sudo docker stop vaultwarden vw_backup
	sudo docker rm vaultwarden vw_backup
