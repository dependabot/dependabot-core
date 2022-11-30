FROM ubuntu:20.04

ARG TARGETARCH=amd64

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

### SYSTEM DEPENDENCIES

ENV DEBIAN_FRONTEND="noninteractive" \
  LC_ALL="en_US.UTF-8" \
  LANG="en_US.UTF-8"

RUN apt-get update \
  && apt-get upgrade -y \
  && apt-get install -y --no-install-recommends \
    build-essential \
    dirmngr \
    git \
    git-lfs \
    bzr \
    mercurial \
    gnupg2 \
    ca-certificates \
    curl \
    file \
    zlib1g-dev \
    liblzma-dev \
    libyaml-dev \
    libgdbm-dev \
    bison \
    tzdata \
    zip \
    unzip \
    locales \
    openssh-client \
    software-properties-common \
    # Everything from here onwards is only installed to ensure
    # Python support works with all packages (which may require
    # specific libraries at install time).
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

# When bumping Ruby minor, need to also add the previous version to `bundler/helpers/v{1,2}/monkey_patches/definition_ruby_version_patch.rb`
ARG RUBY_VERSION=3.1.2
ARG RUBY_INSTALL_VERSION=0.8.5
# Generally simplest to pin RUBYGEMS_SYSTEM_VERSION to the version that default ships with RUBY_VERSION.
ARG RUBYGEMS_SYSTEM_VERSION=3.3.7

ARG BUNDLER_V1_VERSION=1.17.3
# When bumping Bundler, need to also regenerate `updater/Gemfile.lock` via `bundle update --bundler`
ARG BUNDLER_V2_VERSION=2.3.25
ENV BUNDLE_SILENCE_ROOT_WARNING=1
# Allow gem installs as the dependabot user
ENV BUNDLE_PATH=".bundle"

# Install Ruby, update RubyGems, and install Bundler
RUN mkdir -p /tmp/ruby-install \
 && cd /tmp/ruby-install \
 && curl -fsSL "https://github.com/postmodern/ruby-install/archive/v$RUBY_INSTALL_VERSION.tar.gz" -o ruby-install-$RUBY_INSTALL_VERSION.tar.gz  \
 && tar -xzvf ruby-install-$RUBY_INSTALL_VERSION.tar.gz \
 && cd ruby-install-$RUBY_INSTALL_VERSION/ \
 && make \
 && ./bin/ruby-install --system --cleanup ruby $RUBY_VERSION -- --disable-install-doc \
 && gem update --system $RUBYGEMS_SYSTEM_VERSION --no-document \
 && gem install bundler -v $BUNDLER_V1_VERSION --no-document \
 && gem install bundler -v $BUNDLER_V2_VERSION --no-document \
 && rm -rf /var/lib/gems/*/cache/* \
 && rm -rf /tmp/ruby-install


### PYTHON
COPY --chown=dependabot:dependabot python/helpers /opt/python/helpers
# Install Python with pyenv.
USER root
ENV PYENV_ROOT=/usr/local/.pyenv \
  PATH="/usr/local/.pyenv/bin:$PATH"
RUN mkdir -p "$PYENV_ROOT" && chown dependabot:dependabot "$PYENV_ROOT"
USER dependabot
ENV DEPENDABOT_NATIVE_HELPERS_PATH="/opt"
RUN git -c advice.detachedHead=false clone https://github.com/pyenv/pyenv.git --branch v2.3.6 --single-branch --depth=1 /usr/local/.pyenv \
  # This is the version of CPython that gets installed
  && pyenv install 3.11.0 \
  && pyenv global 3.11.0 \
  && pyenv install 3.10.8 \
  && pyenv install 3.9.15 \
  && pyenv install 3.8.15 \
  && pyenv install 3.7.15 \
  && rm -Rf /tmp/python-build* \
  && bash /opt/python/helpers/build \
  && cd /usr/local/.pyenv \
  && tar czf 3.10.tar.gz versions/3.10.8 \
  && tar czf 3.9.tar.gz versions/3.9.15 \
  && tar czf 3.8.tar.gz versions/3.8.15 \
  && tar czf 3.7.tar.gz versions/3.7.15 \
  && rm -Rf versions/3.10.8 \
  && rm -Rf versions/3.9.15 \
  && rm -Rf versions/3.8.15 \
  && rm -Rf versions/3.7.15

USER root
### JAVASCRIPT

# Install Node and npm
RUN curl -sL https://deb.nodesource.com/setup_16.x | bash - \
  && apt-get install -y --no-install-recommends nodejs \
  && rm -rf /var/lib/apt/lists/* \
  && npm install -g npm@8.19.2 \
  && rm -rf ~/.npm

# Install yarn berry and set it to a stable version
RUN corepack enable \
  && corepack prepare yarn@3.2.3 --activate

### ELM

# Install Elm
# This is currently amd64 only, see:
# - https://github.com/elm/compiler/issues/2007
# - https://github.com/elm/compiler/issues/2232
ENV PATH="$PATH:/node_modules/.bin"
RUN [ "$TARGETARCH" != "amd64" ] \
  || (curl -sSLfO "https://github.com/elm/compiler/releases/download/0.19.0/binaries-for-linux.tar.gz" \
  && tar xzf binaries-for-linux.tar.gz \
  && mv elm /usr/local/bin/elm19 \
  && rm -f binaries-for-linux.tar.gz)


### PHP

# Install PHP and Composer
ENV COMPOSER_ALLOW_SUPERUSER=1
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

RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer1 --version=1.10.26
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer --version=2.3.9

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
ARG GOLANG_VERSION=1.19
# You can find the sha here: https://storage.googleapis.com/golang/go${GOLANG_VERSION}.linux-amd64.tar.gz.sha256
ARG GOLANG_AMD64_CHECKSUM=464b6b66591f6cf055bc5df90a9750bf5fbc9d038722bb84a9d56a2bea974be6
ARG GOLANG_ARM64_CHECKSUM=efa97fac9574fc6ef6c9ff3e3758fb85f1439b046573bf434cccb5e012bd00c8

ENV PATH=/opt/go/bin:$PATH
RUN cd /tmp \
  && curl --http1.1 -o go-${TARGETARCH}.tar.gz https://dl.google.com/go/go${GOLANG_VERSION}.linux-${TARGETARCH}.tar.gz \
  && printf "$GOLANG_AMD64_CHECKSUM go-amd64.tar.gz\n$GOLANG_ARM64_CHECKSUM go-arm64.tar.gz\n" | sha256sum -c --ignore-missing - \
  && tar -xzf go-${TARGETARCH}.tar.gz -C /opt \
  && rm go-${TARGETARCH}.tar.gz


### ELIXIR

# Install Erlang and Elixir
ENV PATH="$PATH:/usr/local/elixir/bin"
# https://github.com/elixir-lang/elixir/releases
ARG ELIXIR_VERSION=v1.14.1
ARG ELIXIR_CHECKSUM=610b23ab7f8ffd247a62b187c148cd2aa599b5a595137fe0531664903b921306
ARG ERLANG_MAJOR_VERSION=24
ARG ERLANG_VERSION=1:${ERLANG_MAJOR_VERSION}.2.1-1
RUN curl -sSLfO https://packages.erlang-solutions.com/erlang-solutions_2.0_all.deb \
  && dpkg -i erlang-solutions_2.0_all.deb \
  && apt-get update \
  && apt-get install -y --no-install-recommends esl-erlang=${ERLANG_VERSION} \
  && curl -sSLfO https://github.com/elixir-lang/elixir/releases/download/${ELIXIR_VERSION}/elixir-otp-${ERLANG_MAJOR_VERSION}.zip \
  && echo "$ELIXIR_CHECKSUM  elixir-otp-${ERLANG_MAJOR_VERSION}.zip" | sha256sum -c - \
  && unzip -d /usr/local/elixir -x elixir-otp-${ERLANG_MAJOR_VERSION}.zip \
  && rm -f elixir-otp-${ERLANG_MAJOR_VERSION}.zip erlang-solutions_2.0_all.deb \
  && rm -rf /var/lib/apt/lists/*


### RUST

# Install Rust
ENV RUSTUP_HOME=/opt/rust \
  CARGO_HOME=/opt/rust \
  PATH="${PATH}:/opt/rust/bin"
RUN mkdir -p "$RUSTUP_HOME" && chown dependabot:dependabot "$RUSTUP_HOME"
USER dependabot
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y --default-toolchain 1.64.0 --profile minimal


### Terraform

USER root
ARG TERRAFORM_VERSION=1.3.5
ARG TERRAFORM_AMD64_CHECKSUM=ac28037216c3bc41de2c22724e863d883320a770056969b8d211ca8af3d477cf
ARG TERRAFORM_ARM64_CHECKSUM=ba5b1761046b899197bbfce3ad9b448d14550106d2cc37c52a60fc6822b584ed
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

# https://dart.dev/get-dart/archive
ARG DART_VERSION=2.18.5
# TODO Dart now publishes SHA256 checksums for their releases, we should validate against those.
RUN DART_ARCH=${TARGETARCH} \
  && if [ "$TARGETARCH" = "amd64" ]; then DART_ARCH=x64; fi \
  && curl --connect-timeout 15 --retry 5 "https://storage.googleapis.com/dart-archive/channels/stable/release/${DART_VERSION}/sdk/dartsdk-linux-${DART_ARCH}-release.zip" > "/tmp/dart-sdk.zip" \
  && mkdir -p "$PUB_CACHE" \
  && chown dependabot:dependabot "$PUB_CACHE" \
  && unzip "/tmp/dart-sdk.zip" -d "/opt/dart" > /dev/null \
  && chmod -R o+rx "/opt/dart/dart-sdk" \
  && rm "/tmp/dart-sdk.zip" \
  && dart --version

COPY --chown=dependabot:dependabot LICENSE /home/dependabot

USER dependabot

ENV DEPENDABOT_NATIVE_HELPERS_PATH="/opt"

COPY --chown=dependabot:dependabot composer/helpers /opt/composer/helpers
RUN bash /opt/composer/helpers/v1/build \
  && bash /opt/composer/helpers/v2/build

COPY --chown=dependabot:dependabot bundler/helpers /opt/bundler/helpers
RUN bash /opt/bundler/helpers/v1/build \
  && bash /opt/bundler/helpers/v2/build

COPY --chown=dependabot:dependabot go_modules/helpers /opt/go_modules/helpers
RUN bash /opt/go_modules/helpers/build

COPY --chown=dependabot:dependabot hex/helpers /opt/hex/helpers
ENV MIX_HOME="/opt/hex/mix"
# https://github.com/hexpm/hex/releases
ENV HEX_VERSION="1.0.1"
RUN bash /opt/hex/helpers/build

COPY --chown=dependabot:dependabot pub/helpers /opt/pub/helpers
RUN bash /opt/pub/helpers/build

COPY --chown=dependabot:dependabot npm_and_yarn/helpers /opt/npm_and_yarn/helpers
RUN bash /opt/npm_and_yarn/helpers/build
# Our native helpers pull in yarn 1, so we need to reset the version globally to
# 3.2.3.
RUN corepack prepare yarn@3.2.3 --activate

COPY --chown=dependabot:dependabot terraform/helpers /opt/terraform/helpers
RUN bash /opt/terraform/helpers/build

ENV PATH="$PATH:/opt/terraform/bin:/opt/python/bin:/opt/go_modules/bin"

ENV HOME="/home/dependabot"

WORKDIR ${HOME}

# Place a git shim ahead of git on the path to rewrite git arguments to use HTTPS.
ARG SHIM="https://github.com/dependabot/git-shim/releases/download/v1.4.0/git-v1.4.0-linux-amd64.tar.gz"
RUN curl -sL $SHIM -o git-shim.tar.gz && mkdir -p ~/bin && tar -xvf git-shim.tar.gz -C ~/bin && rm git-shim.tar.gz
ENV PATH="$HOME/bin:$PATH"
# Configure cargo to use git CLI so the above takes effect
RUN mkdir -p ~/.cargo && printf "[net]\ngit-fetch-with-cli = true\n" >> ~/.cargo/config.toml
# Disable automatic pulling of files stored with Git LFS
# This avoids downloading large files not necessary for the dependabot scripts
ENV GIT_LFS_SKIP_SMUDGE=1
