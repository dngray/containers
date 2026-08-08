FROM docker.io/library/alpine:edge

ARG HOST_UID=1003
ARG HOST_GID=1003

# Lock in version arguments matching upstream package dependencies
ARG SNAPCAST_RELEASE

RUN set -ex \
    && echo "**** setup apk testing mirror ****" \
    && echo "@testing https://nl.alpinelinux.org/alpine/edge/testing/" >> /etc/apk/repositories \
    && cat /etc/apk/repositories \
    && echo "**** install runtime packages ****" \
    && apk add --no-cache -U --upgrade \
      alsa-utils \
      dbus \
      tzdata \
      snapcast \
      snapweb@testing \
    # [!] COMMENTED OUT: Removed the third-party streaming binaries to eliminate supply chain risks
    #  librespot@testing \
    #  shairport-sync@testing \
    && echo "**** cleanup ****" \
    && rm -rf /tmp/*

COPY config/snapserver.conf /etc/snapserver.conf
RUN chmod 644 /etc/snapserver.conf

RUN addgroup -g ${HOST_GID} snapserver && adduser -D -u ${HOST_UID} -G snapserver snapserver \
    && mkdir -p /var/lib/snapserver && chown -R snapserver:snapserver /var/lib/snapserver

ENV HOME=/var/lib/snapserver

USER snapserver

EXPOSE 1704 1780
VOLUME ["/config", "/data"]

ENTRYPOINT ["/usr/bin/snapserver"]
CMD []
