#
# murmur
#

.PHONY: murmur
murmur:
	sudo docker run -d \
		--name murmur \
		--hostname mumble \
		--runtime=runsc-kvm \
		--restart=unless-stopped \
		--read-only \
		--memory=8g \
		--pids-limit=2048 \
		--security-opt=no-new-privileges \
		--cap-drop=all \
		-p 64738:64738 \
		--user=1104:1104 \
		--env-file ./murmur.env \
		-v ${c_data}/murmur/config:/murmur/config:rw \
		-v ${c_data}/murmur/data:/murmur/data:rw \
		--network host \
		mumblevoip/mumble-server:latest

murmur-run: murmur-network-create murmur

.PHONY: murmur-clean
murmur-clean:
	sudo docker stop murmur
	sudo docker rm murmur
