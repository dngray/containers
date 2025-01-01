#
# vault
#

.PHONY: vault-net-create
vault-net-create:
	sudo docker network create --subnet=172.23.0.0/16 \
	--ipv6 --subnet fd23:1::/48 \
	vault_frontend

.PHONY: vault
vault:
	sudo docker run -d \
		--name vault \
		--runtime=runsc-kvm \
		--restart=unless-stopped \
		--read-only \
		--memory=8g \
		--pids-limit=2048 \
		--security-opt=no-new-privileges \
		--cap-drop=all \
		--cap-add=IPC_LOCK \
		--cap-add=SETGID \
		--cap-add=SETUID \
		-p 127.0.0.1:8200:8200 \
		--user=1104:1104 \
		-v ${c_data}/vault/config:/vault/config:rw \
		-v ${c_data}/vault/data:/vault/data:rw \
		-e VAULT_ADDR=http://0.0.0.0:8200 \
		-e VAULT_API_ADDR=http://0.0.0.0:8200 \
		-e SKIP_SETCAP=1 \
		-e SKIP_CHOWN=1 \
		--network=vault_frontend --ip=172.23.0.2 \
		docker.io/hashicorp/vault server

vault-run: vault-net-create vault

.PHONY: vault-clean
vault-clean:
	sudo docker stop vault
	sudo docker network rm vault_frontend
	sudo docker rm vault
