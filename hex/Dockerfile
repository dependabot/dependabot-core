FROM ghcr.io/dependabot/dependabot-updater-core
RUN apt-get update \
  && apt-get upgrade -y \
  && apt-get install -y --no-install-recommends \
    gnupg2 libncurses5 libsctp1  

# Install Erlang
# From https://www.erlang-solutions.com/downloads/
ARG ERLANG_MAJOR_VERSION=25
ARG ERLANG_MINOR_VERSION=3.2-1
ARG ERLANG_VERSION=${ERLANG_MAJOR_VERSION}.${ERLANG_MINOR_VERSION}
ARG ERLANG_CHECKSUM=79116f9fe5679376927d02750437f2941b465591c44d4b8304152f0bd89dda00

RUN \
  curl -O https://binaries2.erlang-solutions.com/ubuntu/pool/contrib/e/esl-erlang/esl-erlang_${ERLANG_VERSION}~ubuntu~jammy_amd64.deb && \
  echo "$ERLANG_CHECKSUM esl-erlang_${ERLANG_VERSION}~ubuntu~jammy_amd64.deb" | sha256sum -c - && \
  dpkg -i esl-erlang_${ERLANG_VERSION}~ubuntu~jammy_amd64.deb && \
  rm esl-erlang_${ERLANG_VERSION}~ubuntu~jammy_amd64.deb

# Install Elixir
# https://github.com/elixir-lang/elixir/releases
ARG ELIXIR_VERSION=v1.14.4
ARG ELIXIR_CHECKSUM=a5b7aadfd896e691a6494f9079fcd6f1209adcbd93f2d40e5770d80edc0f33e6
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
