#
# hugo
#

.PHONY: hugo
hugo:
	podman run -it --replace --userns=keep-id \
		-p 1313:1313 \
		-v ~/src/dngray/polarbear-army:/src \
		-v ~/.cache/hugo_cache:/tmp/hugo_cache \
		--security-opt label:disable \
		--name hugo \
		ghcr.io/hugomods/hugo:latest \
		hugo server --bind 0.0.0.0
		# docker.io/hugomods/docker

.PHONY: hugo-clean
hugo-clean:
	podman rm -f hugomods/hugo
	podman image rm hugomods/hugo
