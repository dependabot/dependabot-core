FROM ghcr.io/dependabot/dependabot-updater-core
ARG COMPOSER_V2_VERSION=2.7.7
ENV COMPOSER_ALLOW_SUPERUSER=1
RUN apt-get update \
  && apt-get upgrade -y \
  && apt-get install -y --no-install-recommends \
    software-properties-common
RUN add-apt-repository ppa:ondrej/php \
  && apt-get update \
  && apt-get install -y --no-install-recommends \
    php8.2 \
    php8.2-apcu \
    php8.2-bcmath \
    php8.2-cli \
    php8.2-common \
    php8.2-curl \
    php8.2-gd \
    php8.2-gettext \
    php8.2-gmp \
    php8.2-imagick \
    php8.2-imap \
    php8.2-intl \
    php8.2-ldap \
    php8.2-mbstring \
    php8.2-memcached \
    php8.2-mongodb \
    php8.2-mysql \
    php8.2-redis \
    php8.2-soap \
    php8.2-sqlite3 \
    php8.2-tidy \
    php8.2-xml \
    php8.2-zip \
    php8.2-zmq \
    php8.2-mcrypt \
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
