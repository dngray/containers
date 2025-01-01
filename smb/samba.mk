#
# samba
#

.PHONY: samba
samba:
	sudo docker run -d \
		--name samba \
		--hostname smb \
		--runtime=runsc-kvm \
		--restart=unless-stopped \
		--memory=1g \
		--pids-limit=512 \
		--security-opt=no-new-privileges \
		--cap-drop=all \
		--cap-add=CHOWN \
		--cap-add=DAC_OVERRIDE \
		--cap-add=FOWNER \
		--cap-add=NET_BIND_SERVICE \
		--cap-add=NET_RAW \
		--cap-add=SETGID \
		--cap-add=SETUID \
		-v ${PWD}/smb/config.yml:/data/config.yml \
		-v /home/${u1}:/samba/${u1} \
		-v /home/${u2}:/samba/${u2} \
		-v /mnt/shared:/samba/shared \
		-e "SAMBA_LOG_LEVEL=0" \
		--network host \
		docker.io/crazymax/samba

.PHONY: samba-clean
samba-clean:
	sudo docker stop samba
	sudo docker network rm
	sudo docker rm samba
