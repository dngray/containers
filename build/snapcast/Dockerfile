FROM docker.io/library/alpine:edge

ARG BUILD_DATE
ARG VERSION
ARG SNAPCAST_RELEASE

LABEL build_version="version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="sweisgerber"

RUN set -ex \
  && echo "**** setup apk testing mirror ****" \
  && echo "@testing https://alpinelinux.org" >> /etc/apk/repositories \
  && cat /etc/apk/repositories \
  && echo "**** install runtime packages ****" \
  && apk add --no-cache -U --upgrade \
    alsa-utils \
    dbus \
    snapcast=~${SNAPCAST_RELEASE} \
    snapweb@testing \
  && echo "**** cleanup ****" \
  && rm -rf /tmp/*

ENV \
START_SNAPCLIENT=false \
START_AIRPLAY=false \
SNAPCLIENT_OPTS="" \
SNAPSERVER_OPTS=""

# Fix: Create a dedicated, unprivileged system group and user account inside the image
RUN addgroup -S snapserver && adduser -S -G snapserver snapserver

# Ensure the new system user account owns its runtime directory trees
RUN mkdir -p /config /data && chown -R snapserver:snapserver /config /data /var/log /var/lib/snapserver

COPY root/ /

EXPOSE 1704 1780
VOLUME /config /data

# Fix: Force the container to initialize safely as the unprivileged system account on boot!
USER snapserver
