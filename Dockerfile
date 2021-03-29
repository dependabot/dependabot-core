FROM ubuntu:18.04

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
    curl \
    wget \
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
  && locale-gen en_US.UTF-8

ARG USER_UID=1000
ARG USER_GID=$USER_UID

RUN GROUP_NAME=$(getent group $USER_GID | awk -F':' '{print $1}') \
  && if [ -z $GROUP_NAME ]; then groupadd --gid $USER_GID dependabot ; \
     else groupmod -n dependabot $GROUP_NAME ; fi \
  && useradd --uid "${USER_UID}" --gid "${USER_GID}" -m dependabot \
  && mkdir -p /opt && chown dependabot:dependabot /opt


### RUBY

# Install Ruby 2.6.6, update RubyGems, and install Bundler
ENV BUNDLE_SILENCE_ROOT_WARNING=1
RUN apt-add-repository ppa:brightbox/ruby-ng \
  && apt-get update \
  && apt-get install -y ruby2.6 ruby2.6-dev \
  && gem update --system 3.2.14 \
  && gem install bundler -v 1.17.3 --no-document \
  && gem install bundler -v 2.2.15 --no-document \
  && rm -Rf /var/lib/gems/2.6.0/cache/*


### PYTHON

# Install Python 2.7 and 3.9 with pyenv. Using pyenv lets us support multiple Pythons
ENV PYENV_ROOT=/usr/local/.pyenv \
  PATH="/usr/local/.pyenv/bin:$PATH"
RUN mkdir -p "$PYENV_ROOT" && chown dependabot:dependabot "$PYENV_ROOT"
USER dependabot
RUN git clone https://github.com/pyenv/pyenv.git /usr/local/.pyenv \
  && cd /usr/local/.pyenv && git checkout 1.2.26 && cd - \
  && pyenv install 3.9.4 \
  && pyenv install 2.7.18 \
  && pyenv global 3.9.4
USER root


### JAVASCRIPT

# Install Node 14.0 and npm (updated after elm)
RUN curl -sL https://deb.nodesource.com/setup_14.x | bash - \
  && apt-get install -y nodejs


### ELM

# Install Elm 0.18 and Elm 0.19
ENV PATH="$PATH:/node_modules/.bin"
RUN npm install elm@0.18.0 \
  && wget "https://github.com/elm/compiler/releases/download/0.19.0/binaries-for-linux.tar.gz" \
  && tar xzf binaries-for-linux.tar.gz \
  && mv elm /usr/local/bin/elm19 \
  && rm -f binaries-for-linux.tar.gz \
  && rm -rf ~/.npm

# NOTE: This is a hack to get around the fact that elm 18 fails to install with
# npm 7, we should look into deprecating elm 18
RUN npm install -g npm@v7.7.4


### PHP

# Install PHP 7.4 and Composer
ENV COMPOSER_ALLOW_SUPERUSER=1
COPY --from=composer:1.10.9 /usr/bin/composer /usr/local/bin/composer1
COPY --from=composer:2.0.8 /usr/bin/composer /usr/local/bin/composer
RUN add-apt-repository ppa:ondrej/php \
  && apt-get update \
  && apt-get install -y \
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
    php7.4-zmq


### GO

# Install Go and dep
ARG GOLANG_VERSION=1.16.2
ARG GOLANG_CHECKSUM=542e936b19542e62679766194364f45141fde55169db2d8d01046555ca9eb4b8
ENV PATH=/opt/go/bin:$PATH \
  GOPATH=/opt/go/gopath
RUN cd /tmp \
  && curl --http1.1 -o go.tar.gz https://dl.google.com/go/go${GOLANG_VERSION}.linux-amd64.tar.gz \
  && echo "$GOLANG_CHECKSUM go.tar.gz" | sha256sum -c - \
  && tar -xzf go.tar.gz -C /opt \
  && rm go.tar.gz \
  && mkdir "$GOPATH" \
  && chown dependabot:dependabot "$GOPATH" \
  && wget -O /opt/go/bin/dep https://github.com/golang/dep/releases/download/v0.5.4/dep-linux-amd64 \
  && chmod +x /opt/go/bin/dep


### ELIXIR

# Install Erlang, Elixir and Hex
ENV PATH="$PATH:/usr/local/elixir/bin"
# https://github.com/elixir-lang/elixir/releases
ARG ELIXIR_VERSION=v1.10.4
ARG ELIXIR_CHECKSUM=9727ae96d187d8b64e471ff0bb5694fcd1009cdcfd8b91a6b78b7542bb71fca59869d8440bb66a2523a6fec025f1d23394e7578674b942274c52b44e19ba2d43
RUN wget https://packages.erlang-solutions.com/erlang-solutions_1.0_all.deb \
  && dpkg -i erlang-solutions_1.0_all.deb \
  && apt-get update \
  && apt-get install -y esl-erlang \
  && wget https://github.com/elixir-lang/elixir/releases/download/${ELIXIR_VERSION}/Precompiled.zip \
  && echo "$ELIXIR_CHECKSUM  Precompiled.zip" | sha512sum -c - \
  && unzip -d /usr/local/elixir -x Precompiled.zip \
  && rm -f Precompiled.zip erlang-solutions_1.0_all.deb \
  && mix local.hex --force


### RUST

# Install Rust 1.51.0
ENV RUSTUP_HOME=/opt/rust \
  CARGO_HOME=/opt/rust \
  PATH="${PATH}:/opt/rust/bin"
RUN mkdir -p "$RUSTUP_HOME" && chown dependabot:dependabot "$RUSTUP_HOME"
USER dependabot
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y \
  && rustup toolchain install 1.51.0 && rustup default 1.51.0
USER root

COPY --chown=dependabot:dependabot composer/helpers /opt/composer/helpers
COPY --chown=dependabot:dependabot dep/helpers /opt/dep/helpers
COPY --chown=dependabot:dependabot bundler/helpers /opt/bundler/helpers
COPY --chown=dependabot:dependabot go_modules/helpers /opt/go_modules/helpers
COPY --chown=dependabot:dependabot hex/helpers /opt/hex/helpers
COPY --chown=dependabot:dependabot npm_and_yarn/helpers /opt/npm_and_yarn/helpers
COPY --chown=dependabot:dependabot python/helpers /opt/python/helpers
COPY --chown=dependabot:dependabot terraform/helpers /opt/terraform/helpers

ENV DEPENDABOT_NATIVE_HELPERS_PATH="/opt" \
  PATH="$PATH:/opt/terraform/bin:/opt/python/bin:/opt/go_modules/bin:/opt/dep/bin" \
  MIX_HOME="/opt/hex/mix"

USER dependabot
RUN mkdir -p /opt/bundler/v1 \
  && mkdir -p /opt/bundler/v2 \
  && bash /opt/bundler/helpers/v1/build /opt/bundler/v1 \
  && bash /opt/bundler/helpers/v2/build /opt/bundler/v2 \
  && bash /opt/dep/helpers/build /opt/dep \
  && bash /opt/go_modules/helpers/build /opt/go_modules \
  && bash /opt/hex/helpers/build /opt/hex \
  && bash /opt/npm_and_yarn/helpers/build /opt/npm_and_yarn \
  && bash /opt/python/helpers/build /opt/python \
  && bash /opt/terraform/helpers/build /opt/terraform \
  && bash /opt/composer/helpers/v1/build /opt/composer/v1 \
  && bash /opt/composer/helpers/v2/build /opt/composer/v2

# Allow further gem installs as the dependabot user
ENV BUNDLE_PATH="/home/dependabot/.bundle" \
    BUNDLE_BIN=".bundle/bin" \
    PATH=".bundle/bin:$PATH:/home/dependabot/.bundle/bin"
