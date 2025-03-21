#
# proton-bridge
# https://github.com/shenxn/protonmail-bridge-docker
#

pm-bridge-init:
	podman run --rm -it \
		--name protonmail-bridge \
		-v ${c_data}/pm_bridge:/root \
		docker.io/shenxn/protonmail-bridge init \
		shenxn/protonmail-bridge init

pm-bridge:
	podman run --rm -it --replace \
		--name protonmail-bridge \
		-v ${c_data}/pm_bridge:/root \
		-p 1025:25/tcp \
		-p 1143:143/tcp \
		docker.io/shenxn/protonmail-bridge

pm-bridge-clean:
	podman rm -f docker.io/shenxn/protonmail
	podman image rm docker.io/shenxn/protonmail
