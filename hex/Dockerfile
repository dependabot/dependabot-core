# syntax=docker.io/docker/dockerfile:1.20
FROM ghcr.io/dependabot/dependabot-updater-core
RUN apt-get update \
  && apt-get upgrade -y \
  && apt-get install -y --no-install-recommends \
  gnupg2 sudo curl apt-transport-https

ARG ERLANG_MAJOR_VERSION=27

# Install Erlang/OTP from the CloudAMQP packagecloud mirror of Erlang Solutions.
#
# History:
#   * Originally `esl-erlang` was used from packages.erlang-solutions.com, but
#     that repo has no working Jammy support (Release file missing, no arm64),
#     see https://github.com/esl/packages/issues/15.
#   * We then switched to the RabbitMQ Launchpad PPA (rabbitmq-erlang-27).
#     That PPA only publishes the arch-independent metapackages (erlang,
#     erlang-nox, ...) for arm64; the actual binary packages such as
#     erlang-base / erlang-crypto are amd64-only. On arm64 apt silently fell
#     back to Ubuntu Jammy's default Erlang (OTP 24), which then failed to
#     load Elixir's OTP-27-compiled BEAM files with:
#       {undef,[{elixir,start_cli,[],[]}, ...]}
#   * CloudAMQP maintains a packagecloud mirror of Erlang Solutions which
#     does ship `esl-erlang` for both amd64 and arm64 on Jammy, so we use it.
#
# The base Ubuntu `apt` erlang version should not be used--it is too old.

# CloudAMQP packagecloud signing key
RUN curl -1sLf "https://packagecloud.io/cloudamqp/erlang/gpgkey" | sudo gpg --dearmor | sudo tee /usr/share/keyrings/io.packagecloud.cloudamqp.erlang.gpg > /dev/null

RUN echo "deb [signed-by=/usr/share/keyrings/io.packagecloud.cloudamqp.erlang.gpg] https://packagecloud.io/cloudamqp/erlang/ubuntu/ jammy main" > /etc/apt/sources.list.d/cloudamqp-erlang.list

# `esl-erlang` is a self-contained Erlang/OTP package (it bundles all the
# applications such as crypto/ssl/inets/etc. that we previously selected
# individually). We pin it to the requested OTP major version via a wildcard
# so this Dockerfile keeps tracking the latest patch release on the chosen
# OTP line.
RUN apt-get update \
  && apt-get install -y --no-install-recommends "esl-erlang=1:${ERLANG_MAJOR_VERSION}.*"

# Install Elixir
# https://github.com/elixir-lang/elixir/releases
ARG ELIXIR_VERSION=v1.19.5
ARG ELIXIR_CHECKSUM=1ab3154ec19adcd4b764cf96badecbe44df5ec6f358dc0fbe29c3749ff6c08de
RUN curl -sSLfO https://github.com/elixir-lang/elixir/releases/download/${ELIXIR_VERSION}/elixir-otp-${ERLANG_MAJOR_VERSION}.zip \
  && echo "$ELIXIR_CHECKSUM  elixir-otp-${ERLANG_MAJOR_VERSION}.zip" | sha256sum -c - \
  && unzip -d /usr/local/elixir -x elixir-otp-${ERLANG_MAJOR_VERSION}.zip \
  && rm -f elixir-otp-${ERLANG_MAJOR_VERSION}.zip
ENV PATH="$PATH:/usr/local/elixir/bin"

USER dependabot

COPY --chown=dependabot:dependabot hex/helpers /opt/hex/helpers
ENV MIX_HOME="/opt/hex/mix"
# https://github.com/hexpm/hex/releases
ENV HEX_VERSION="2.3.1"
ENV HEX_CACERTS_PATH=/etc/ssl/certs/ca-certificates.crt
RUN bash /opt/hex/helpers/build

COPY --chown=dependabot:dependabot --parents hex common $DEPENDABOT_HOME/
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
