#
# Imapfilter
#

imapfilter-build:
	podman build -f build/imapfilter/Containerfile \
		--build-arg BUILD_DATE=$(date -u) \
		-t imapfilter:latest

imapfilter:
	podman run --replace --userns=keep-id \
		-v ~/.config/imapfilter:/home/imapfilter/.config/imapfilter:z,ro \
		-v ~/.vault-token:/home/imapfilter/.vault-token:z,ro \
		--name imapfilter \
		--cap-add=IPC_LOCK \
		-e VAULT_ADDR \
		localhost/imapfilter

imapfilter-clean:
	podman rm -f localhost/imapfilter
	podman image rm localhost/imapfilter
