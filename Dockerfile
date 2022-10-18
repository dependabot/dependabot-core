FROM ubuntu:20.04

# dart arguments
ARG DART_VERSION=2.17.0

# elixer arguments
ARG ELIXIR_VERSION=v1.13.4
ARG ELIXIR_CHECKSUM=e64c714e80cd9657b8897d725f6d78f251d443082f6af5070caec863c18068c97af6bdda156c3b3390e0a2b84f77c2ad3378a42913f64bb583fb5251fa49e619

# erlang arguments
ARG ERLANG_VERSION=1:24.2.1-1

# golang arguments
ARG GOLANG_VERSION=1.19
ARG GOLANG_AMD64_CHECKSUM=464b6b66591f6cf055bc5df90a9750bf5fbc9d038722bb84a9d56a2bea974be6
ARG GOLANG_ARM64_CHECKSUM=efa97fac9574fc6ef6c9ff3e3758fb85f1439b046573bf434cccb5e012bd00c8

# ruby arguments
ARG BUNDLER_V1_VERSION=1.17.3
ARG BUNDLER_V2_VERSION=2.3.22
ARG RUBY_INSTALL_VERSION=0.8.3
ARG RUBY_VERSION=3.1.2
ARG RUBYGEMS_SYSTEM_VERSION=3.3.22

# system arguments
ARG TARGETARCH=amd64
ARG USER_GID=$USER_UID
ARG USER_UID=1000

# git arguments
# place a git shim ahead of git on the path to rewrite git arguments to use HTTPS.
ARG SHIM="https://github.com/dependabot/git-shim/releases/download/v1.4.0/git-v1.4.0-linux-amd64.tar.gz"

# terraform arguments
ARG TERRAFORM_VERSION=1.3.2
ARG TERRAFORM_AMD64_CHECKSUM=6372e02a7f04bef9dac4a7a12f4580a0ad96a37b5997e80738e070be330cb11c
ARG TERRAFORM_ARM64_CHECKSUM=ce1a8770aaf27736a3352c5c31e95fb10d0944729b9d81013bf6848f8657da5f

# fail on any shell command failures
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV \
  # system environment variables
  DEBIAN_FRONTEND="noninteractive" \
  LC_ALL="en_US.UTF-8" \
  LANG="en_US.UTF-8" \
  # ruby environment variables
  BUNDLE_SILENCE_ROOT_WARNING=1 \
  BUNDLE_PATH=".bundle" \
  BUNDLE_BIN=".bundle/bin" \
  PATH="$BUNDLE_BIN:$PATH:$BUNDLE_PATH/bin" \
  # python environment variables
  PYENV_ROOT="/usr/local/.pyenv" \
  PATH="/usr/local/.pyenv/bin:$PATH" \
  PATH="$PATH:/opt/python/bin" \
  # elm environment variables
  PATH="$PATH:/node_modules/.bin" \
  # composer environment variables
  COMPOSER_ALLOW_SUPERUSER=1 \
  # golang environment variables
  PATH="/opt/go/bin:$PATH" \
  PATH="$PATH:/opt/go_modules/bin" \
  # hex envrionment variables
  MIX_HOME="/opt/hex/mix" \
  # elixer environment variables
  PATH="$PATH:/usr/local/elixir/bin" \
  # rust environment variables
  RUSTUP_HOME="/opt/rust" \
  CARGO_HOME="/opt/rust" \
  PATH="${PATH}:/opt/rust/bin" \
  # dart environment variables
  PUB_CACHE=/opt/dart/pub-cache \
  PUB_ENVIRONMENT="dependabot" \
  PATH="${PATH}:/opt/dart/dart-sdk/bin" \
  # dependabot environment variables
  DEPENDABOT_NATIVE_HELPERS_PATH="/opt" \
  HOME="/home/dependabot" \
  PATH="$HOME/bin:$PATH" \
  # terraform environment variables
  PATH="$PATH:/opt/terraform/bin"

# install composer
COPY --from=composer:1.10.26 /usr/bin/composer /usr/local/bin/composer1
COPY --from=composer:2.3.9 /usr/bin/composer /usr/local/bin/composer

# install system dependencies
RUN apt-get update \
  && apt-get upgrade -y \
  && apt-get install -y --no-install-recommends \
    bison \
    build-essential \
    bzr \
    ca-certificates \
    curl \
    dirmngr \
    file \
    git \
    gnupg2 \
    libgdbm-dev \
    liblzma-dev \
    libyaml-dev \
    locales \
    mercurial \
    openssh-client \
    software-properties-common \
    tzdata \
    unzip \
    zip \
    zlib1g-dev \
    # install supporting python packages that may require specific libraries at install time
    libbz2-dev \
    libcurl4-openssl-dev \
    libffi-dev \
    libgeos-dev \
    libmysqlclient-dev \
    libncurses5-dev \
    libncursesw5-dev \
    libpq-dev \
    libreadline-dev \
    libsqlite3-dev \
    libssl-dev \
    libxml2-dev \
    libxmlsec1-dev \
    llvm \
    make \
    python3-enchant \
    tk-dev \
    xz-utils \
  && locale-gen en_US.UTF-8 \
  && rm -rf /var/lib/apt/lists/* \
  # add the dependabot user and group if they don't exist
  && if ! getent group "$USER_GID"; then \
       groupadd --gid "$USER_GID" dependabot \
     else \
       GROUP_NAME=$(getent group $USER_GID | awk -F':' '{print $1}'); groupmod -n dependabot "$GROUP_NAME" \
     fi \
  && useradd --uid "${USER_UID}" --gid "${USER_GID}" -m dependabot \
  && mkdir -p /opt && chown dependabot:dependabot /opt \
  # install ruby, update rubygems, and install budler
  && mkdir -p /tmp/ruby-install \
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
  && rm -rf /tmp/ruby-install \
  # install python with pyenv
  && mkdir -p "$PYENV_ROOT" && chown dependabot:dependabot "$PYENV_ROOT" \
  && runuser -l dependabot -c "git -c advice.detachedHead=false clone https://github.com/pyenv/pyenv.git --branch v2.3.5 --single-branch --depth=1 /usr/local/.pyenv \
                              # this is the version of CPython that gets installed
                              && pyenv install 3.10.7 \
                              && pyenv global 3.10.7 \
                              && rm -Rf /tmp/python-build*" \
  # install node and npm
  && curl -sL https://deb.nodesource.com/setup_16.x | bash - \
  && apt-get install -y --no-install-recommends nodejs \
  && rm -rf /var/lib/apt/lists/* \
  && npm install -g npm@8.19.2 \
  && rm -rf ~/.npm \
  # install yarn berry and set it to a stable version
  && corepack enable \
  && corepack prepare yarn@3.2.3 --activate \
  # install elm (amd64 only - https://github.com/elm/compiler/issues/2007, https://github.com/elm/compiler/issues/2232)
  && [ "$TARGETARCH" != "amd64" ] || (curl -sSLfO "https://github.com/elm/compiler/releases/download/0.19.0/binaries-for-linux.tar.gz" \
                                       && tar xzf binaries-for-linux.tar.gz \
                                       && mv elm /usr/local/bin/elm19 \
                                       && rm -f binaries-for-linux.tar.gz) \
  # install php
  && add-apt-repository ppa:ondrej/php \
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
  && rm -rf /var/lib/apt/lists/* \
  && runuser -l dependabot -c "mkdir /tmp/composer-cache \
                              && cd /tmp/composer-cache \
                              && echo '{'require':{'psr/log': '^1.1.3'}}' > composer.json \
                              && composer update --no-scripts --dry-run \
                              && cd /tmp \
                              && rm -rf /home/dependabot/.cache/composer/files \
                              && rm -rf /tmp/composer-cache" \
  # install go
  && cd /tmp \
  && curl --http1.1 -o go-${TARGETARCH}.tar.gz https://dl.google.com/go/go${GOLANG_VERSION}.linux-${TARGETARCH}.tar.gz \
  && printf "$GOLANG_AMD64_CHECKSUM go-amd64.tar.gz\n$GOLANG_ARM64_CHECKSUM go-arm64.tar.gz\n" | sha256sum -c --ignore-missing - \
  && tar -xzf go-${TARGETARCH}.tar.gz -C /opt \
  && rm go-${TARGETARCH}.tar.gz \
  # install erlang, elixer, and hex
  && curl -sSLfO https://packages.erlang-solutions.com/erlang-solutions_2.0_all.deb \
  && dpkg -i erlang-solutions_2.0_all.deb \
  && apt-get update \
  && apt-get install -y --no-install-recommends esl-erlang=${ERLANG_VERSION} \
  && curl -sSLfO https://github.com/elixir-lang/elixir/releases/download/${ELIXIR_VERSION}/Precompiled.zip \
  && echo "$ELIXIR_CHECKSUM  Precompiled.zip" | sha512sum -c - \
  && unzip -d /usr/local/elixir -x Precompiled.zip \
  && rm -f Precompiled.zip erlang-solutions_2.0_all.deb \
  && mix local.hex --force \
  && rm -rf /var/lib/apt/lists/* \
  # install rust
  && mkdir -p "$RUSTUP_HOME" && chown dependabot:dependabot "$RUSTUP_HOME" \
  && runuser -l dependabot -c "curl https://sh.rustup.rs -sSf | sh -s -- -y --default-toolchain 1.64.0 --profile minimal" \
  # install terraform
  && cd /tmp \
  && curl -o terraform-${TARGETARCH}.tar.gz https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${TARGETARCH}.zip \
  && printf "$TERRAFORM_AMD64_CHECKSUM terraform-amd64.tar.gz\n$TERRAFORM_ARM64_CHECKSUM terraform-arm64.tar.gz\n" | sha256sum -c --ignore-missing - \
  && unzip -d /usr/local/bin terraform-${TARGETARCH}.tar.gz \
  && rm terraform-${TARGETARCH}.tar.gz \
  # install dart
  && DART_ARCH=${TARGETARCH} \
  && if [ "$TARGETARCH" = "amd64" ]; then DART_ARCH=x64; fi \
  && curl --connect-timeout 15 --retry 5 "https://storage.googleapis.com/dart-archive/channels/stable/release/${DART_VERSION}/sdk/dartsdk-linux-${DART_ARCH}-release.zip" > "/tmp/dart-sdk.zip" \
  && mkdir -p "$PUB_CACHE" \
  && chown dependabot:dependabot "$PUB_CACHE" \
  && unzip "/tmp/dart-sdk.zip" -d "/opt/dart" > /dev/null \
  && chmod -R o+rx "/opt/dart/dart-sdk" \
  && rm "/tmp/dart-sdk.zip" \
  && dart --version

COPY --chown=dependabot:dependabot LICENSE /home/dependabot
COPY --chown=dependabot:dependabot composer/helpers /opt/composer/helpers
COPY --chown=dependabot:dependabot bundler/helpers /opt/bundler/helpers
COPY --chown=dependabot:dependabot go_modules/helpers /opt/go_modules/helpers
COPY --chown=dependabot:dependabot hex/helpers /opt/hex/helpers
COPY --chown=dependabot:dependabot pub/helpers /opt/pub/helpers
COPY --chown=dependabot:dependabot npm_and_yarn/helpers /opt/npm_and_yarn/helpers
COPY --chown=dependabot:dependabot python/helpers /opt/python/helpers
COPY --chown=dependabot:dependabot terraform/helpers /opt/terraform/helpers

USER dependabot

RUN bash /opt/composer/helpers/v1/build \
  && bash /opt/composer/helpers/v2/build \
  && bash /opt/bundler/helpers/v1/build \
  && bash /opt/bundler/helpers/v2/build \
  && bash /opt/go_modules/helpers/build \
  && MIX_HOME="/opt/hex/mix" \
  && bash /opt/hex/helpers/build \
  && bash /opt/pub/helpers/build \
  && bash /opt/npm_and_yarn/helpers/build \
  # our native helpers pull in yarn 1, so we need to reset the version globally to 3.2.3
  && corepack prepare yarn@3.2.3 --activate \
  && bash /opt/python/helpers/build \
  && bash /opt/terraform/helpers/build \
  && curl -sL $SHIM -o git-shim.tar.gz && mkdir -p ~/bin && tar -xvf git-shim.tar.gz -C ~/bin && rm git-shim.tar.gz \
  && mkdir -p ~/.cargo \
  # configure cargo to use git CLI so the git shiim takes effect
  && printf "[net]\ngit-fetch-with-cli = true\n" >> ~/.cargo/config.toml

WORKDIR ${HOME}
