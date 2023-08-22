FROM ghcr.io/dependabot/dependabot-updater-core
RUN apt-get update \
  && apt-get upgrade -y \
  && apt-get install -y --no-install-recommends \
    gnupg2

# Install Erlang
ARG ERLANG_MAJOR_VERSION=24
ARG ERLANG_VERSION=1:${ERLANG_MAJOR_VERSION}.3.4.13-1

# We install from the RabbitMQ Erlang PPAs: https://www.rabbitmq.com/install-debian.html#apt-cloudsmith
RUN curl -1sLf "https://keys.openpgp.org/vks/v1/by-fingerprint/0A9AF2115F4687BD29803A206B73A36E6026DFCA" | gpg --dearmor | tee /usr/share/keyrings/com.rabbitmq.team.gpg > /dev/null \
  && curl -1sLf https://ppa.novemberain.com/gpg.E495BB49CC4BBE5B.key | gpg --dearmor | tee /usr/share/keyrings/rabbitmq.E495BB49CC4BBE5B.gpg > /dev/null \
  && tee /etc/apt/sources.list.d/rabbitmq.list <<EOF
    ## Provides modern Erlang/OTP releases
    ##
    deb [signed-by=/usr/share/keyrings/rabbitmq.E495BB49CC4BBE5B.gpg] https://ppa1.novemberain.com/rabbitmq/rabbitmq-erlang/deb/ubuntu focal main
    deb-src [signed-by=/usr/share/keyrings/rabbitmq.E495BB49CC4BBE5B.gpg] https://ppa1.novemberain.com/rabbitmq/rabbitmq-erlang/deb/ubuntu focal main

    # another mirror for redundancy
    deb [signed-by=/usr/share/keyrings/rabbitmq.E495BB49CC4BBE5B.gpg] https://ppa2.novemberain.com/rabbitmq/rabbitmq-erlang/deb/ubuntu focal main
    deb-src [signed-by=/usr/share/keyrings/rabbitmq.E495BB49CC4BBE5B.gpg] https://ppa2.novemberain.com/rabbitmq/rabbitmq-erlang/deb/ubuntu focal main
EOF

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    erlang-base=${ERLANG_VERSION} \
    erlang-asn1=${ERLANG_VERSION} \
    erlang-crypto=${ERLANG_VERSION} \
    erlang-eldap=${ERLANG_VERSION} \
    erlang-ftp=${ERLANG_VERSION} \
    erlang-inets=${ERLANG_VERSION} \
    erlang-mnesia=${ERLANG_VERSION} \
    erlang-os-mon=${ERLANG_VERSION} \
    erlang-parsetools=${ERLANG_VERSION} \
    erlang-public-key=${ERLANG_VERSION} \
    erlang-runtime-tools=${ERLANG_VERSION} \
    erlang-snmp=${ERLANG_VERSION} \
    erlang-ssl=${ERLANG_VERSION} \
    erlang-syntax-tools=${ERLANG_VERSION} \
    erlang-tftp=${ERLANG_VERSION} \
    erlang-tools=${ERLANG_VERSION} \
    erlang-xmerl=${ERLANG_VERSION} \
  && rm -rf /etc/apt/sources.list.d/* /usr/share/keyrings/rabbitmq.E495BB49CC4BBE5B.gpg /usr/share/keyrings/rabbitmq.E495BB49CC4BBE5B.gpg
# TODO the above `rm` doesn't work as expected since it's a separate RUN layer, but lets at least try to get this working, we can collapse to a single layer later...

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
