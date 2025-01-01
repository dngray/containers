#
# flexo
#

.PHONY: flexo-network-create
flexo-network-create:
	sudo docker network create --subnet=172.26.0.0/16 \
	--ipv6 --subnet fd26:1::/48 \
	flexo_frontend

.PHONY: flexo
flexo:
	sudo docker run -d \
		--name flexo \
		--runtime=runsc-kvm \
		--restart=unless-stopped \
		--read-only \
		--memory=8g \
		--pids-limit=2048 \
		--security-opt=no-new-privileges \
		--cap-drop=all \
		--user=1105:1105 \
		-p 9898:9898/tcp \
		--env-file=${PWD}/flexo/flexo.env \
		-v ${c_data}/flexo/latency_test_results.json:/var/cache/flexo/state/latency_test_results.json \
		-v /mnt/shared/flexo:/var/cache/flexo/pkg \
		--network=flexo_frontend --ip=172.26.0.2 \
		docker.io/nroi/flexo

.PHONY: flexo-run
flexo-run: flexo-network-create flexo

.PHONY: flexo-clean
flexo-clean:
	sudo docker stop flexo
	sudo docker network rm flexo_frontend
	sudo docker rm flexo
