FROM docker.io/library/alpine:edge

RUN set -ex \
    && echo "@testing https://nl.alpinelinux.org/alpine/edge/testing/" >> /etc/apk/repositories \
    && apk add --no-cache \
        snapcast \
    && rm -rf /tmp/*

COPY snapclient-entrypoint.sh /usr/local/bin/
RUN chmod 755 /usr/local/bin/snapclient-entrypoint.sh

ENV SNAPCAST_PORT=1704

ENTRYPOINT ["snapclient-entrypoint.sh"]
