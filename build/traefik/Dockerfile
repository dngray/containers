ARG TRAEFIK_VERSION=3.7.5
ARG CHECKSUM=9da81a928fde965c2c4678698bbc28bc3f600223b14c32b35bd480bf5ec863dc
FROM alpine AS downloader

ARG TRAEFIK_VERSION
ARG CHECKSUM

RUN wget --quiet -O /tmp/traefik.tar.gz https://github.com/traefik/traefik/releases/download/v${TRAEFIK_VERSION}/traefik_v${TRAEFIK_VERSION}_linux_amd64.tar.gz \
 && CHECKSUM_STATE=$(echo -n $(echo "${CHECKSUM}  /tmp/traefik.tar.gz" | sha256sum -c) | tail -c 2) \
 && if [ "${CHECKSUM_STATE}" != "OK" ]; then echo "Error: checksum does not match" && exit 1; fi \
 && tar xzvf /tmp/traefik.tar.gz -C /usr/local/bin traefik \
 && rm -f /tmp/traefik.tar.gz \
 && chmod +x /usr/local/bin/traefik


FROM gcr.io/distroless/static-debian13
COPY --from=downloader /usr/local/bin/traefik /
EXPOSE 8080 4430
USER nobody
ENTRYPOINT ["/traefik"]
