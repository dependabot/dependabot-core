FROM ghcr.io/dependabot/dependabot-updater-core
ARG COMPOSER_V2_VERSION=2.8.11
ARG PHP_VERSION=8.4
ENV COMPOSER_ALLOW_SUPERUSER=1
RUN apt-get update \
  && apt-get upgrade -y \
  && apt-get install -y --no-install-recommends \
    software-properties-common
RUN add-apt-repository ppa:ondrej/php \
  && apt-get update \
  && apt-get install -y --no-install-recommends \
    php${PHP_VERSION} \
    php${PHP_VERSION}-apcu \
    php${PHP_VERSION}-bcmath \
    php${PHP_VERSION}-cli \
    php${PHP_VERSION}-common \
    php${PHP_VERSION}-curl \
    php${PHP_VERSION}-gd \
    php${PHP_VERSION}-gettext \
    php${PHP_VERSION}-gmp \
    php${PHP_VERSION}-imagick \
    php${PHP_VERSION}-imap \
    php${PHP_VERSION}-intl \
    php${PHP_VERSION}-ldap \
    php${PHP_VERSION}-mbstring \
    php${PHP_VERSION}-memcached \
    php${PHP_VERSION}-mongodb \
    php${PHP_VERSION}-mysql \
    php${PHP_VERSION}-redis \
    php${PHP_VERSION}-soap \
    php${PHP_VERSION}-sqlite3 \
    php${PHP_VERSION}-tidy \
    php${PHP_VERSION}-xml \
    php${PHP_VERSION}-zip \
    php${PHP_VERSION}-zmq \
    php${PHP_VERSION}-mcrypt \
  && rm -rf /var/lib/apt/lists/*

RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer --version=${COMPOSER_V2_VERSION}

USER dependabot
# Perform a fake `composer update` to warm ~/dependabot/.cache/composer/repo
# with historic data (we don't care about package files here)
RUN mkdir /tmp/composer-cache \
  && cd /tmp/composer-cache \
  && echo '{"require":{"psr/log": "^1.1.3"}}' > composer.json \
  && composer update --no-scripts --dry-run \
  && cd /tmp \
  && rm -rf /home/dependabot/.cache/composer/files \
  && rm -rf /tmp/composer-cache

COPY --chown=dependabot:dependabot composer/helpers /opt/composer/helpers

RUN bash /opt/composer/helpers/v2/build

COPY --chown=dependabot:dependabot composer $DEPENDABOT_HOME/composer
COPY --chown=dependabot:dependabot common $DEPENDABOT_HOME/common
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
