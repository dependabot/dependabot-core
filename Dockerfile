FROM ubuntu:20.04

ARG TARGETARCH=amd64

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

### SYSTEM DEPENDENCIES

ENV DEBIAN_FRONTEND="noninteractive" \
  LC_ALL="en_US.UTF-8" \
  LANG="en_US.UTF-8"

# Everything from `make` onwards in apt-get install is only installed to ensure
# Python support works with all packages (which may require specific libraries
# at install time).
RUN apt-get update \
  && apt-get upgrade -y \
  && apt-get install -y --no-install-recommends \
    build-essential \
    dirmngr \
    git \
    bzr \
    mercurial \
    gnupg2 \
    ca-certificates \
    curl \
    file \
    zlib1g-dev \
    liblzma-dev \
    tzdata \
    zip \
    unzip \
    locales \
    openssh-client \
    software-properties-common \
    make \
    libpq-dev \
    libssl-dev \
    libbz2-dev \
    libffi-dev \
    libreadline-dev \
    libsqlite3-dev \
    libcurl4-openssl-dev \
    llvm \
    libncurses5-dev \
    libncursesw5-dev \
    libmysqlclient-dev \
    xz-utils \
    tk-dev \
    libxml2-dev \
    libxmlsec1-dev \
    libgeos-dev \
    python3-enchant \
  && locale-gen en_US.UTF-8 \
  && rm -rf /var/lib/apt/lists/*

ARG USER_UID=1000
ARG USER_GID=$USER_UID

RUN if ! getent group "$USER_GID"; then groupadd --gid "$USER_GID" dependabot ; \
     else GROUP_NAME=$(getent group $USER_GID | awk -F':' '{print $1}'); groupmod -n dependabot "$GROUP_NAME" ; fi \
  && useradd --uid "${USER_UID}" --gid "${USER_GID}" -m dependabot \
  && mkdir -p /opt && chown dependabot:dependabot /opt


### RUBY

# Install Ruby 2.7, update RubyGems, and install Bundler
ENV BUNDLE_SILENCE_ROOT_WARNING=1
# Disable the outdated rubygems installation from being loaded
ENV DEBIAN_DISABLE_RUBYGEMS_INTEGRATION=true
# Allow gem installs as the dependabot user
ENV BUNDLE_PATH=".bundle" \
    BUNDLE_BIN=".bundle/bin"
ENV PATH="$BUNDLE_BIN:$PATH:$BUNDLE_PATH/bin"
RUN apt-add-repository ppa:brightbox/ruby-ng \
  && apt-get update \
  && apt-get install -y --no-install-recommends ruby2.7 ruby2.7-dev \
  && gem update --system 3.2.20 \
  && gem install bundler -v 1.17.3 --no-document \
  && gem install bundler -v 2.3.13 --no-document \
  && rm -rf /var/lib/gems/2.7.0/cache/* \
  && rm -rf /var/lib/apt/lists/*


### PYTHON

# Install Python 3.10 with pyenv.
ENV PYENV_ROOT=/usr/local/.pyenv \
  PATH="/usr/local/.pyenv/bin:$PATH"
RUN mkdir -p "$PYENV_ROOT" && chown dependabot:dependabot "$PYENV_ROOT"
USER dependabot
RUN git clone https://github.com/pyenv/pyenv.git --branch v2.2.5 --single-branch --depth=1 /usr/local/.pyenv \
  && pyenv install 3.10.3 \
  && pyenv global 3.10.3 \
  && rm -Rf /tmp/python-build*
USER root


### JAVASCRIPT

# Install Node 16.0 and npm v8
RUN curl -sL https://deb.nodesource.com/setup_16.x | bash - \
  && apt-get install -y --no-install-recommends nodejs \
  && rm -rf /var/lib/apt/lists/* \
  && npm install -g npm@v8.5.1 \
  && rm -rf ~/.npm


### ELM

# Install Elm 0.19
# This is amd64 only, see:
# - https://github.com/elm/compiler/issues/2007
# - https://github.com/elm/compiler/issues/2232
ENV PATH="$PATH:/node_modules/.bin"
RUN [ "$TARGETARCH" != "amd64" ] \
  || (curl -sSLfO "https://github.com/elm/compiler/releases/download/0.19.0/binaries-for-linux.tar.gz" \
  && tar xzf binaries-for-linux.tar.gz \
  && mv elm /usr/local/bin/elm19 \
  && rm -f binaries-for-linux.tar.gz)


### PHP

# Install PHP 7.4 and Composer
ENV COMPOSER_ALLOW_SUPERUSER=1
COPY --from=composer:1.10.26 /usr/bin/composer /usr/local/bin/composer1
COPY --from=composer:2.3.5 /usr/bin/composer /usr/local/bin/composer
RUN add-apt-repository ppa:ondrej/php \
  && apt-get update \
  && apt-get install -y --no-install-recommends \
    php7.4 \
    php7.4-apcu \
    php7.4-bcmath \
    php7.4-cli \
    php7.4-common \
    php7.4-curl \
    php7.4-gd \
    php7.4-geoip \
    php7.4-gettext \
    php7.4-gmp \
    php7.4-imagick \
    php7.4-imap \
    php7.4-intl \
    php7.4-json \
    php7.4-ldap \
    php7.4-mbstring \
    php7.4-memcached \
    php7.4-mongodb \
    php7.4-mysql \
    php7.4-redis \
    php7.4-soap \
    php7.4-sqlite3 \
    php7.4-tidy \
    php7.4-xml \
    php7.4-zip \
    php7.4-zmq \
    php7.4-mcrypt \
  && rm -rf /var/lib/apt/lists/*
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
USER root


### GO

# Install Go
ARG GOLANG_VERSION=1.18.1
# You can find the sha here: https://storage.googleapis.com/golang/go${GOLANG_VERSION}.linux-amd64.tar.gz.sha256
ARG GOLANG_AMD64_CHECKSUM=b3b815f47ababac13810fc6021eb73d65478e0b2db4b09d348eefad9581a2334
ARG GOLANG_ARM64_CHECKSUM=56a91851c97fb4697077abbca38860f735c32b38993ff79b088dac46e4735633

ENV PATH=/opt/go/bin:$PATH
RUN cd /tmp \
  && curl --http1.1 -o go-${TARGETARCH}.tar.gz https://dl.google.com/go/go${GOLANG_VERSION}.linux-${TARGETARCH}.tar.gz \
  && printf "$GOLANG_AMD64_CHECKSUM go-amd64.tar.gz\n$GOLANG_ARM64_CHECKSUM go-arm64.tar.gz\n" | sha256sum -c --ignore-missing - \
  && tar -xzf go-${TARGETARCH}.tar.gz -C /opt \
  && rm go-${TARGETARCH}.tar.gz


### ELIXIR

# Install Erlang, Elixir and Hex
ENV PATH="$PATH:/usr/local/elixir/bin"
# https://github.com/elixir-lang/elixir/releases
ARG ELIXIR_VERSION=v1.12.3
ARG ELIXIR_CHECKSUM=db092caa32b55195eeb24a17e0ab98bb2fea38d2f638bc42fee45a6dfcd3ba0782618d27e281c545651f93914481866b9d34b6d284c7f763d197e87847fdaef4
ARG ERLANG_VERSION=1:24.2.1-1
RUN curl -sSLfO https://packages.erlang-solutions.com/erlang-solutions_2.0_all.deb \
  && dpkg -i erlang-solutions_2.0_all.deb \
  && apt-get update \
  && apt-get install -y --no-install-recommends esl-erlang=${ERLANG_VERSION} \
  && curl -sSLfO https://github.com/elixir-lang/elixir/releases/download/${ELIXIR_VERSION}/Precompiled.zip \
  && echo "$ELIXIR_CHECKSUM  Precompiled.zip" | sha512sum -c - \
  && unzip -d /usr/local/elixir -x Precompiled.zip \
  && rm -f Precompiled.zip erlang-solutions_2.0_all.deb \
  && mix local.hex --force \
  && rm -rf /var/lib/apt/lists/*


### RUST

# Install Rust 1.59.0
ENV RUSTUP_HOME=/opt/rust \
  CARGO_HOME=/opt/rust \
  PATH="${PATH}:/opt/rust/bin"
RUN mkdir -p "$RUSTUP_HOME" && chown dependabot:dependabot "$RUSTUP_HOME"
USER dependabot
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y --default-toolchain 1.59.0 --profile minimal


### Terraform

USER root
ARG TERRAFORM_VERSION=1.1.6
ARG TERRAFORM_AMD64_CHECKSUM=3e330ce4c8c0434cdd79fe04ed6f6e28e72db44c47ae50d01c342c8a2b05d331
ARG TERRAFORM_ARM64_CHECKSUM=a53fb63625af3572f7252b9fb61d787ab153132a8984b12f4bb84b8ee408ec53
RUN cd /tmp \
  && curl -o terraform-${TARGETARCH}.tar.gz https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${TARGETARCH}.zip \
  && printf "$TERRAFORM_AMD64_CHECKSUM terraform-amd64.tar.gz\n$TERRAFORM_ARM64_CHECKSUM terraform-arm64.tar.gz\n" | sha256sum -c --ignore-missing - \
  && unzip -d /usr/local/bin terraform-${TARGETARCH}.tar.gz \
  && rm terraform-${TARGETARCH}.tar.gz

### DART

# Install Dart
ENV PUB_CACHE=/opt/dart/pub-cache \
  PUB_ENVIRONMENT="dependabot" \
  PATH="${PATH}:/opt/dart/dart-sdk/bin"

ARG DART_VERSION=2.16.2
RUN DART_ARCH=${TARGETARCH} \
  && if [ "$TARGETARCH" = "amd64" ]; then DART_ARCH=x64; fi \
  && curl --connect-timeout 15 --retry 5 "https://storage.googleapis.com/dart-archive/channels/stable/release/${DART_VERSION}/sdk/dartsdk-linux-${DART_ARCH}-release.zip" > "/tmp/dart-sdk.zip" \
  && mkdir -p "$PUB_CACHE" \
  && chown dependabot:dependabot "$PUB_CACHE" \
  && unzip "/tmp/dart-sdk.zip" -d "/opt/dart" > /dev/null \
  && chmod -R o+rx "/opt/dart/dart-sdk" \
  && rm "/tmp/dart-sdk.zip" \
  && dart --version
# We pull the dependency_services from the dart-lang/pub repo as it is not
# exposed from the Dart SDK (yet...).
RUN git clone https://github.com/dart-lang/pub.git /opt/dart/pub \
  && git -C /opt/dart/pub checkout 62bb244059415cf0c78b24151472efd46ad7569a \
  && dart pub global activate --source path /opt/dart/pub \
  && chmod -R o+r "/opt/dart/pub" \
  && chown -R dependabot:dependabot "$PUB_CACHE" \
  && chown -R dependabot:dependabot /opt/dart/pub

# Install Flutter
ARG FLUTTER_VERSION=2.10.3
RUN curl --connect-timeout 15 --retry 5 "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" > "/tmp/flutter.xz" \
  && tar xf "/tmp/flutter.xz" -C /opt/dart \
  && rm "/tmp/flutter.xz" \
  && chmod -R o+rx "/opt/dart/flutter" \
  && chown -R dependabot:dependabot "/opt/dart/flutter" \
  # To reduce space usage we delete all of the flutter sdk except the few
  # things needed for pub resolutions:
  # * The version file
  # * The flutter sdk packages.
  && find "/opt/dart/flutter" \
    ! -path '/opt/dart/flutter/version' \
    ! -path '/opt/dart/flutter/packages/*' \
    ! -path '/opt/dart/flutter/packages' \
    ! -path '/opt/dart/flutter/bin/cache/pkg/*' \
    ! -path /opt/dart/flutter/bin/cache/pkg \
    ! -path /opt/dart/flutter/bin/cache \
    ! -path /opt/dart/flutter/bin \
    ! -path /opt/dart/flutter \
    -delete

COPY --chown=dependabot:dependabot LICENSE /home/dependabot
COPY --chown=dependabot:dependabot composer/helpers /opt/composer/helpers
COPY --chown=dependabot:dependabot bundler/helpers /opt/bundler/helpers
COPY --chown=dependabot:dependabot go_modules/helpers /opt/go_modules/helpers
COPY --chown=dependabot:dependabot hex/helpers /opt/hex/helpers
COPY --chown=dependabot:dependabot npm_and_yarn/helpers /opt/npm_and_yarn/helpers
COPY --chown=dependabot:dependabot python/helpers /opt/python/helpers
COPY --chown=dependabot:dependabot terraform/helpers /opt/terraform/helpers

ENV DEPENDABOT_NATIVE_HELPERS_PATH="/opt" \
  PATH="$PATH:/opt/terraform/bin:/opt/python/bin:/opt/go_modules/bin" \
  MIX_HOME="/opt/hex/mix"

USER dependabot
RUN bash /opt/bundler/helpers/v1/build
RUN bash /opt/bundler/helpers/v2/build
RUN bash /opt/composer/helpers/v1/build
RUN bash /opt/composer/helpers/v2/build
RUN bash /opt/go_modules/helpers/build
RUN bash /opt/hex/helpers/build
RUN bash /opt/npm_and_yarn/helpers/build
RUN bash /opt/python/helpers/build
RUN bash /opt/terraform/helpers/build

ENV HOME="/home/dependabot"

WORKDIR ${HOME}
