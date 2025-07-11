FROM ghcr.io/dependabot/dependabot-updater-core
ARG COMPOSER_V2_VERSION=2.8.9
ENV COMPOSER_ALLOW_SUPERUSER=1
RUN apt-get update \
  && apt-get upgrade -y \
  && apt-get install -y --no-install-recommends \
    software-properties-common
RUN add-apt-repository ppa:ondrej/php \
  && apt-get update \
  && apt-get install -y --no-install-recommends \
    php8.4 \
    php8.4-apcu \
    php8.4-bcmath \
    php8.4-cli \
    php8.4-common \
    php8.4-curl \
    php8.4-gd \
    php8.4-gettext \
    php8.4-gmp \
    php8.4-imagick \
    php8.4-imap \
    php8.4-intl \
    php8.4-ldap \
    php8.4-mbstring \
    php8.4-memcached \
    php8.4-mongodb \
    php8.4-mysql \
    php8.4-redis \
    php8.4-soap \
    php8.4-sqlite3 \
    php8.4-tidy \
    php8.4-xml \
    php8.4-zip \
    php8.4-zmq \
    php8.4-mcrypt \
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
