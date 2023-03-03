FROM ghcr.io/dependabot/dependabot-updater-core
RUN apt-get update \
  && apt-get upgrade -y \
  && apt-get install -y --no-install-recommends \
    gnupg2 sudo curl apt-transport-https

ARG ERLANG_MAJOR_VERSION=26

# This is using https://www.rabbitmq.com/docs/install-debian#apt-launchpad-erlang to install erlang. Previously, esl-erlang was used, but it does not
# contain arm architecture packages. The base `apt` erlang version should not be used--it is too old.

# primary RabbitMQ signing key
RUN curl -1sLf "https://github.com/rabbitmq/signing-keys/releases/download/3.0/rabbitmq-release-signing-key.asc" | sudo gpg --dearmor | sudo tee /usr/share/keyrings/com.github.rabbitmq.signing.gpg > /dev/null

# Launchpad PPA signing key for apt
RUN curl -1sLf "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xf77f1eda57ebb1cc" | sudo gpg --dearmor | sudo tee /usr/share/keyrings/net.launchpad.ppa.rabbitmq.erlang.gpg > /dev/null

RUN echo "deb [signed-by=/usr/share/keyrings/net.launchpad.ppa.rabbitmq.erlang.gpg] https://ppa.launchpadcontent.net/rabbitmq/rabbitmq-erlang-${ERLANG_MAJOR_VERSION}/ubuntu jammy main" >> /etc/apt/sources.list
RUN echo "deb-src [signed-by=/usr/share/keyrings/net.launchpad.ppa.rabbitmq.erlang.gpg] https://ppa.launchpadcontent.net/rabbitmq/rabbitmq-erlang-${ERLANG_MAJOR_VERSION}/ubuntu jammy main" >> /etc/apt/sources.list

# The `erlang` package from rabbitmq includes large packages, like erlang-wx, that aren't needed for this.
RUN apt-get update \
  && apt-get install -y --no-install-recommends erlang-base \
  erlang-asn1 erlang-crypto erlang-eldap erlang-ftp erlang-inets \
  erlang-mnesia erlang-os-mon erlang-parsetools erlang-public-key \
  erlang-runtime-tools erlang-snmp erlang-ssh erlang-ssl \
  erlang-syntax-tools erlang-tftp erlang-tools erlang-xmerl

# Install Elixir
# https://github.com/elixir-lang/elixir/releases
ARG ELIXIR_VERSION=v1.18.1
ARG ELIXIR_CHECKSUM=aae4625102ba7020887918d1c0ac7c8ad972b65fe8103476765cc6b00ab16b5f
RUN curl -sSLfO https://github.com/elixir-lang/elixir/releases/download/${ELIXIR_VERSION}/elixir-otp-${ERLANG_MAJOR_VERSION}.zip \
  && echo "$ELIXIR_CHECKSUM  elixir-otp-${ERLANG_MAJOR_VERSION}.zip" | sha256sum -c - \
  && unzip -d /usr/local/elixir -x elixir-otp-${ERLANG_MAJOR_VERSION}.zip \
  && rm -f elixir-otp-${ERLANG_MAJOR_VERSION}.zip
ENV PATH="$PATH:/usr/local/elixir/bin"

USER dependabot

COPY --chown=dependabot:dependabot hex/helpers /opt/hex/helpers
ENV MIX_HOME="/opt/hex/mix"
# https://github.com/hexpm/hex/releases
ENV HEX_VERSION="2.0.6"
RUN bash /opt/hex/helpers/build

COPY --chown=dependabot:dependabot hex $DEPENDABOT_HOME/hex
COPY --chown=dependabot:dependabot common $DEPENDABOT_HOME/common
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
