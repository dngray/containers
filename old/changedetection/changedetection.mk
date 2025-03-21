#
# changedetection
#
include global.env

.PHONY: changedetection-network-create
changedetection-network-create:
	sudo docker network create --subnet=172.30.0.0/16 \
	--ipv6 --subnet fd30:1::/48 \
	changedetection_frontend

.PHONY: changedetection
changedetection:
	sudo docker run \
		--name changedetection \
		--runtime=runsc-kvm \
		--restart=unless-stopped \
		--read-only \
		--memory=8g \
		--pids-limit=2048 \
		--security-opt=no-new-privileges \
		--cap-drop=all \
		--user=1300:1300 \
		--network=changedetection_frontend --ip=172.30.0.2 \
		-p 127.0.0.1:5000:5000 \
		-v ${c_data}/changedetection:/datastore \
		ghcr.io/dgtlmoon/changedetection.io

.PHONY: changedetection-run
changedetection-run: changedetection-network-create changedetection

.PHONY: changedetection-clean
changedetection-clean:
	sudo docker stop changedetection
	sudo docker network rm changedetection_frontend
	sudo docker rm changedetection
