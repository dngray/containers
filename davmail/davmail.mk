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
		-e DAVMAIL_SERVER=true \
		-e DAVMAIL_ALLOWREMOTE=true \
		-e DAVMAIL_DISABLEUPDATECHECK=true \
		-e DAVMAIL_LOGFILEPATH=/dev/stdout \
		-e DAVMAIL_CALDAVPORT=1080 \
		-e DAVMAIL_IMAPPORT=1143 \
		-e DAVMAIL_LDAPPORT=1389 \
		-e DAVMAIL_POPPORT=1110 \
		-e DAVMAIL_SMTPPORT=1025 \
		-e DAVMAIL_MODE=O365Manual \
		-e DAVMAIL_OAUTH_TOKENFILEPATH=/davmail-token \
		-e DAVMAIL_OAUTH_CLIENTID=d3590ed6-52b3-4102-aeff-aad2292ab01c \
		-e DAVMAIL_OAUTH_REDIRECTURI=urn:ietf:wg:oauth:2.0:oob \
		-e JAVA_OPTS="-Xmx512M -Dsun.net.inetaddr.ttl=30n" \
		-p 1080:1080 \
		-p 1143:1143 \
		-p 1389:1389 \
		-p 1110:1110 \
		-p 1025:1025 \
		-v ~/.config/davmail:/davmail-token \
		--name davmail \
		localhost/davmail

.PHONY: davmail-clean
davmail-clean:
	podman rm -f localhost/davmail
	podman image rm localhost/davmail
