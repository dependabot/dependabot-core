FROM ghcr.io/dependabot/dependabot-updater-core
RUN apt-get update \
  && apt-get upgrade -y \
  && apt-get install -y --no-install-recommends \
    gnupg2

# Install Erlang
# Note: Currently we install from Ubuntu PPA to unblock upgrading to Ubuntu 22.04, but we'd be happy to accept a PR
# switching to a more up to date PPA. See also:
#  * https://github.com/esl/packages/issues/15
#  * https://github.com/dependabot/dependabot-core/pull/7865
#  * https://erlangforums.com/t/erlang-solutions-apt-package-for-otp-25/1552/1
#  * https://erlangforums.com/t/the-eef-is-looking-for-volunteers-to-take-over-esls-build-packages/2238/1
ARG ERLANG_MAJOR_VERSION=25
ARG ERLANG_VERSION=1:${ERLANG_MAJOR_VERSION}.3.2.8+dfsg-1ubuntu4
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    erlang=${ERLANG_VERSION}

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
