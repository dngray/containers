FROM alpine:3.24.1 AS builder


ARG JOSE_COMMIT_SHA=41176df01b679cbd577d2bfa99c211cce145e3d2
ARG TANG_COMMIT_SHA=97cffa4e2b7e60c7f363571a2acdf596effac575


RUN apk add --no-cache --update \
            bash \
            g++ gawk git gmp gzip \
            http-parser-dev \
            isl-dev \
            jansson-dev \
            meson mpc1-dev mpfr-dev musl-dev \
            ninja \
            openssl-dev \
            tar \
            zlib-dev

RUN git clone https://github.com/latchset/jose.git \
 && cd jose \
 && git checkout ${JOSE_COMMIT_SHA} \
 && mkdir build \
 && cd build \
 && meson .. --prefix=/usr/local \
 && ninja install

RUN git clone https://github.com/latchset/tang.git \
 && cd tang \
 && git checkout ${TANG_COMMIT_SHA} \
 && mkdir build \
 && cd build \
 && meson .. --prefix=/usr/local \
 && ninja install




FROM padhihomelab/alpine-base:3.24.1_0.19.0_0.3


COPY --from=builder \
     /usr/local/bin/jose \
     /usr/local/bin/jose
COPY --from=builder \
     /usr/local/lib/libjose.so.0  \
     /usr/local/lib/libjose.so.0
COPY --from=builder \
     /usr/local/lib/libjose.so.0.0.0 \
     /usr/local/lib/libjose.so.0.0.0

COPY --from=builder \
     /usr/local/libexec/tangd \
     /usr/local/bin/tangd
COPY --from=builder \
     /usr/local/libexec/tangd-keygen \
     /usr/local/bin/tangd-keygen

# local patch over padhi-homelab/docker_tang: upstream relies on COPY + "chmod +x",
# which bakes in the build context's file modes. Under a restrictive umask those are
# 0640/0750, and "chmod +x" turns 0640 into 0751 -- executable but unreadable by the
# unprivileged DOCKER_UID the entrypoint drops to, so /bin/sh cannot open the script.
# --chmod=0755 pins the modes instead (same as aerc-bridge/mail-sync Containerfiles).
COPY --chmod=0755 entrypoint-scripts \
     /etc/docker-entrypoint.d/99-extra-scripts
COPY --chmod=0755 check-servers.sh \
     /usr/local/bin/check-servers
COPY --chmod=0755 start-servers.sh \
     /usr/local/bin/start-servers


RUN apk add --no-cache --update \
            http-parser \
            jansson \
            openssl \
            socat \
            wget \
            zlib


EXPOSE 8080
VOLUME [ "/db" ]


ENV ENABLE_IPv4=1
ENV ENABLE_IPv6=0

CMD "start-servers"


HEALTHCHECK --start-period=5s --timeout=3s \
        CMD "check-servers"
