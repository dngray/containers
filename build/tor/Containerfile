FROM alpine:latest

RUN echo '@edge https://dl-cdn.alpinelinux.org/alpine/edge/community' >> /etc/apk/repositories && \
    apk -U upgrade && \
    apk -v add tor@edge torsocks@edge && \
    sed "1s/^/SocksPort 0.0.0.0:9050\n/" /etc/tor/torrc.sample > /etc/tor/torrc.config && \
    rm -rf /var/cache/apk/* /tmp/* /var/tmp/*

EXPOSE 9050

VOLUME ["/var/lib/tor"]

RUN chown -R tor /etc/tor

USER tor

ENTRYPOINT [ "tor", "-f", "/etc/tor/torrc.config" ]
