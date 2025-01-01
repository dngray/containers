#
# pg
#

.PHONY: pg
pg:
	podman run -it --replace \
		-p 127.0.0.1:8000:8000 \
		-v ${PWD}:/docs:z \
		--name pg \
		--entrypoint "sh" ghcr.io/squidfunk/mkdocs-material:9.5.18 \
		-c "git submodule init; git submodule update theme/assets/brand; apk add bash; /bin/bash run.sh --cmd=mkdocs --cmd_flags=--dev-addr=0.0.0.0:8000"

.PHONY: pg-team
pg-team:
	podman run -it --replace --userns=keep-id \
		-v ${PWD}:/site:z \
		-p 127.0.0.1:8000:8000 \
		--name pg-team \
		ghcr.io/privacyguides/privacyguides.org:main

.PHONY: pg-clean
pg-clean:
	podman rm -f ghcr.io/squidfunk/mkdocs-material:latest ghcr.io/privacyguides/privacyguides.org:main
	podman image rm ghcr.io/squidfunk/mkdocs-material:latest ghcr.io/privacyguides/privacyguides.org:main
