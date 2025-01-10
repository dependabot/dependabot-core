FROM ghcr.io/dependabot/dependabot-updater-core
ARG COMPOSER_V2_VERSION=2.7.7
ENV COMPOSER_ALLOW_SUPERUSER=1

# Update the base image and install required packages
RUN apt-get update \
  && apt-get upgrade -y \
  && apt-get install -y --no-install-recommends \
    software-properties-common \
  && add-apt-repository ppa:ondrej/php \
  && apt-get update \
  && apt-get install -y --no-install-recommends \
    php8.1 \
    php8.1-apcu \
    php8.1-bcmath \
    php8.1-cli \
    php8.1-common \
    php8.1-curl \
    php8.1-gd \
    php8.1-gettext \
    php8.1-gmp \
    php8.1-imagick \
    php8.1-imap \
    php8.1-intl \
    php8.1-ldap \
    php8.1-mbstring \
    php8.1-memcached \
    php8.1-mongodb \
    php8.1-mysql \
    php8.1-redis \
    php8.1-soap \
    php8.1-sqlite3 \
    php8.1-tidy \
    php8.1-xml \
    php8.1-zip \
    php8.1-zmq \
    php8.1-mcrypt \
  && rm -rf /var/lib/apt/lists/*

# Install Composer
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
