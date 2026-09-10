FROM docker.io/library/alpine:edge

ARG BUILD_DATE
ARG VCS_REF
ARG HOST_UID=1003
ARG HOST_GID=1003

LABEL org.opencontainers.image.authors="Tobias Hargesheimer <docker@ison.ws>" \
    org.opencontainers.image.title="MPD" \
    org.opencontainers.image.description="MPD - Music Player Daemon" \
    org.opencontainers.image.licenses="GPL-2.0" \
    org.opencontainers.image.created="${BUILD_DATE}" \
    org.opencontainers.image.revision="${VCS_REF}" \
    org.opencontainers.image.url="https://hub.docker.com/r/tobi312/rpi-mpd" \
    org.opencontainers.image.source="https://github.com/Tob1as/docker-mpd"

COPY mpd.conf /etc/mpd.conf

RUN set -eux ; \
    apk --no-cache add \
        mpd \
        mpc \
        tzdata \
        soxr \
    ; \
    deluser mpd 2>/dev/null || true ; \
    delgroup mpd 2>/dev/null || true ; \
    addgroup -g ${HOST_GID} mpd ; \
    adduser -D -u ${HOST_UID} -G mpd mpd ; \
    adduser mpd audio ; \
    mkdir -p /var/lib/mpd/data /var/lib/mpd/playlists ; \
    touch /var/lib/mpd/data/database \
        /var/lib/mpd/data/state \
        /var/lib/mpd/data/sticker.sql \
    ; \
    chown -R mpd:mpd /var/lib/mpd ; \
    chown mpd:audio /etc/mpd.conf

VOLUME /var/lib/mpd
WORKDIR /var/lib/mpd
EXPOSE 6600 8000

USER mpd

CMD ["/usr/bin/mpd", "--no-daemon", "--stdout", "/etc/mpd.conf"]
