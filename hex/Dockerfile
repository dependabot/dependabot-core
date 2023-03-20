FROM ghcr.io/dependabot/dependabot-updater-core
RUN apt-get update \
  && apt-get upgrade -y \
  && apt-get install -y --no-install-recommends \
    gnupg2
# Install Erlang and Elixir
ENV PATH="$PATH:/usr/local/elixir/bin"
# https://github.com/elixir-lang/elixir/releases
ARG ELIXIR_VERSION=v1.14.2
ARG ELIXIR_CHECKSUM=2e4addb85de85218d32c16b3710e8087f5b18b3b1560742137ad4c41bbbea63a
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

USER dependabot

COPY --chown=dependabot:dependabot hex/helpers /opt/hex/helpers
ENV MIX_HOME="/opt/hex/mix"
# https://github.com/hexpm/hex/releases
ENV HEX_VERSION="1.0.1"
RUN bash /opt/hex/helpers/build

COPY --chown=dependabot:dependabot hex /home/dependabot/hex
