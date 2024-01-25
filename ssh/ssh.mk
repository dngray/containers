#
# ssh
#

.PHONY: ssh
ssh:
	sudo docker run -d \
		--name ssh \
		--hostname ssh \
		--runtime=runsc-kvm \
		--restart=unless-stopped \
		--cpus=4 \
		--memory=8g \
		--pids-limit=2048 \
		--security-opt=no-new-privileges \
		--cap-drop=all \
		--cap-add=CHOWN \
		--cap-add=DAC_READ_SEARCH \
		--cap-add=SETGID \
		--cap-add=SETUID \
		-e PUID=1000 \
		-e PGID=1000 \
		-p 2222:2222 \
		-v ${c_data}/ssh/config:/config \
		-e PUBLIC_KEY_DIR=${c_data}/ssh/pubkeys \
		-e SUDO_ACCESS=false \
		-e PASSWORD_ACCESS=false \
		-e USER_NAME=${NAME} \
		--network host \
		lscr.io/linuxserver/openssh-server:latest

.PHONY: ssh-clean
ssh-clean:
	sudo docker stop ssh
	sudo docker container rm ssh
