#
# mailctl
#

.PHONY: mailctl-build
mailctl-build:
	podman build -f mailctl/Containerfile \
		--build-arg BUILD_DATE=$(date -u) \
		--build-arg UID=1000 \
		-t mailctl:latest

.PHONY: mailctl
mailctl:
	podman run -it --replace --userns=keep-id \
		-v ~/.config/mailctl:/home/mailctl/.config/mailctl:z \
		-p 8080:8080 \
		--name mailctl \
		localhost/mailctl

.PHONY: mailctl-clean
mailctl-clean:
	podman rm -f localhost/mailctl
	podman image rm localhost/mailctl
