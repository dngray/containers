FROM alpine:3.16

ARG IMAGE_VERSION
ARG BUILD_DATE

LABEL version="$IMAGE_VERSION"
LABEL created="$BUILD_DATE"

RUN echo "@testing https://dl-cdn.alpinelinux.org/alpine/edge/testing" >> /etc/apk/repositories

RUN apk add --no-cache \
        imapfilter@testing

CMD [ "crond", "-l", "2", "-f" ]
