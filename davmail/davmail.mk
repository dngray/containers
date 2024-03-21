#
# davmail
#

.PHONY: davmail-build
davmail-build:
	podman build -f davmail/Dockerfile \
		-t davmail:latest

.PHONY: davmail
davmail:
	podman run -it --replace --userns=keep-id \
		-p 1143:1143 \
		-p 1025:1025 \
		-v ~/.config/davmail/davmail_manual.properties:/davmail/davmail.properties:ro,z \
		-v ~/.local/lib/davmail/tokens.properties:/davmail/tokens.properties:z \
		-v ~/.local/log/davmail/davmail.log:/davmail/davmail.log:z \
		--name davmail \
		localhost/davmail /davmail/davmail.properties

.PHONY: davmail-clean
davmail-clean:
	podman rm -f localhost/davmail
	podman image rm localhost/davmail
