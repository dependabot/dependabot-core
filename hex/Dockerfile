FROM ghcr.io/dependabot/dependabot-updater-core
RUN apt-get update \
  && apt-get upgrade -y \
  && apt-get install -y --no-install-recommends \
    gnupg2

# Install Erlang
# https://www.erlang-solutions.com/downloads
ARG ERLANG_MAJOR_VERSION=26
ARG ERLANG_VERSION=${ERLANG_MAJOR_VERSION}.0.2-1~ubuntu~jammy_amd64
RUN curl -sSLfO https://binaries2.erlang-solutions.com/ubuntu/pool/contrib/e/esl-erlang/esl-erlang_${ERLANG_VERSION}.deb \
  && dpkg -i esl-erlang_${ERLANG_VERSION}.deb \
  && rm -f esl-erlang_${ERLANG_VERSION}.deb \
  && rm -rf /var/lib/apt/lists/*

# Install Elixir
# https://github.com/elixir-lang/elixir/releases
ARG ELIXIR_VERSION=v1.14.4
ARG ELIXIR_CHECKSUM=b5705275d62ce3dae172d25d7ea567fffdabb45458abeb29c0189923b907367c
RUN curl -sSLfO https://github.com/elixir-lang/elixir/releases/download/${ELIXIR_VERSION}/elixir-otp-${ERLANG_MAJOR_VERSION}.zip \
  && echo "$ELIXIR_CHECKSUM  elixir-otp-${ERLANG_MAJOR_VERSION}.zip" | sha256sum -c - \
  && unzip -d /usr/local/elixir -x elixir-otp-${ERLANG_MAJOR_VERSION}.zip \
  && rm -f elixir-otp-${ERLANG_MAJOR_VERSION}.zip
ENV PATH="$PATH:/usr/local/elixir/bin"

USER dependabot

COPY --chown=dependabot:dependabot hex/helpers /opt/hex/helpers
ENV MIX_HOME="/opt/hex/mix"
# https://github.com/hexpm/hex/releases
ENV HEX_VERSION="1.0.1"
RUN bash /opt/hex/helpers/build

COPY --chown=dependabot:dependabot hex $DEPENDABOT_HOME/hex
COPY --chown=dependabot:dependabot common $DEPENDABOT_HOME/common
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
