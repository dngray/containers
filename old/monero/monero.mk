# TODO
# monero
#
# Notes
# gvisor sets the no_new_privs bit by default
# https://www.kernel.org/doc/Documentation/prctl/no_new_privs.txt
#
# Container also uses fixuid https://github.com/boxboat/fixuid which states:
# fixuid should only be used in development Docker containers. DO NOT INCLUDE
# in a production container image

.PHONY: monero
monero:
	sudo docker run \
		--name=monerod \
		--runtime=runsc-kvm \
		--restart=unless-stopped \
		--memory=8g \
		--pids-limit=2048 \
		--cap-drop=all \
		--cap-add=CHOWN \
		--cap-add=DAC_READ_SEARCH \
		--cap-add=SETGID \
		--cap-add=SETUID \
		--user 1003:1003 \
		--network=container:wg3 \
		-v ${c_data}/monero/.bitmonero:/home/monero/.bitmonero \
		ghcr.io/sethforprivacy/simple-monerod:latest \
			--rpc-restricted-bind-ip=0.0.0.0 \
			--rpc-restricted-bind-port=18089 \
			--no-igd \
			--no-zmq \
			--enable-dns-blocklist

monero-run: monero-network-create monero-vpn-create monero

.PHONY: monero-up
monero-up:
	sudo docker compose --env-file global.env \
		-f monero/compose.yml \
		up

.PHONY: monero-clean
monero-clean:
	sudo docker stop monero_vpn monero
	sudo docker network rm monero_frontend
	sudo docker rm monero_vpn monero
