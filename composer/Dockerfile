FROM composer AS builder

ENV DEPENDABOT_ENV="production"

COPY helpers /opt/composer/helpers
RUN /opt/composer/helpers/build /opt/composer

FROM dependabot/dependabot-common

RUN apk add --no-cache \
        php7 \
        php7-json \
        php7-openssl \
        php7-phar \
        php7-zip \
        php7-zlib

COPY --from=builder /opt/composer/helpers /opt/composer/helpers
