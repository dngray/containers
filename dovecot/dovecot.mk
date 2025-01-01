#
# Dovecot
#

.PHONY: dovecot
dovecot:
	podman run --rm --replace --userns=keep-id \
		-p 143:143/tcp \
		-p 993:993/tcp \
		-p 587:587/tcp \
		-v ./dovecot.conf:/etc/dovecot/dovecot.conf:z \
		-v ./passwd:/etc/dovecot/passwd:z \
		-v ~/Mail:/srv/mail \
		--name dovecot \
		--cap-add=SYS_CHROOT \
		--cap-add=NET_BIND_SERVICE \
		docker.io/dovecot/dovecot

.PHONY: dovecot-clean
dovecot-clean:
	podman rm -f docker.io/dovecot/dovecot
	podman image rm docker.io/dovecot/dovecot
