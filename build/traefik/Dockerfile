ARG TRAEFIK_VERSION=3.6.6
ARG CHECKSUM=9c3c675b39ffbeb53516372fd2298b8aca4b7b29b8de9dd707eda1433fe887b1
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
