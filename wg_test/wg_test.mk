#
# wg_test
#
include global.env
include wg_test/.env

IMAGE_NAME=ghcr.io/wfg/wireguard
WGT_GIT_REF=master
.PHONY: wireguard-client-build
wireguard-client-build:
	sudo docker buildx build ./build/wireguard -f build/wireguard/Dockerfile \
	--build-arg "WGT_GIT_REF=${WGT_GIT_REF}" \
	--tag "${IMAGE_NAME}:latest"

.PHONY: wireguard-client
wireguard-client:
	sudo docker run \
		--runtime=runc \
		--name wireguard \
		--cap-add NET_ADMIN \
		--sysctl net.ipv4.conf.all.src_valid_mark=1 \
		--volume ~/data/wireguard/${WG}.conf:/etc/wireguard/wg0.conf \
		-e ALLOWED_SUBNETS=${NETWORK}.0/24 \
		ghcr.io/wfg/wireguard

.PHONY: wireguard-client-clean
wireguard-client-clean:
	sudo docker stop wireguard
	sudo docker rm wireguard
	sudo docker rmi ghcr.io/wfg/wireguard
