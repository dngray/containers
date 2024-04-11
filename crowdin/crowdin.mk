#
# crowdin
#

.PHONY: crowdin
crowdin-pull:
	podman pull \
		docker.io/crowdin/cli

crowdin:
	podman run -it --replace --userns=keep-id \
		-v ~/src:/src:z \
		--env-file crowdin/.env \
		--name crowdin \
		docker.io/crowdin/cli

.PHONY: crowdin-clean
crowdin-clean:
	podman rm -f docker.io/crowdin/cli
	podman image rm docker.io/crowdin/cli
