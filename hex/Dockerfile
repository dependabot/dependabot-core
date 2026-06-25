# syntax=docker.io/docker/dockerfile:1.20
ARG ELIXIR_VERSION=1.19.5
ARG ERLANG_VERSION=28.4.3
ARG UBUNTU_VERSION=noble-20260410

FROM hexpm/elixir:${ELIXIR_VERSION}-erlang-${ERLANG_VERSION}-ubuntu-${UBUNTU_VERSION} AS elixir-builder

RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*

COPY hex/helpers /opt/hex/helpers
ENV MIX_HOME="/opt/hex/mix"
# https://github.com/hexpm/hex/releases
ENV HEX_VERSION="2.3.1"
ENV HEX_CACERTS_PATH=/etc/ssl/certs/ca-certificates.crt
ENV DEPENDABOT_NATIVE_HELPERS_PATH="/opt/hex/native"
RUN bash /opt/hex/helpers/build

FROM ghcr.io/dependabot/dependabot-updater-core
COPY --from=elixir-builder /opt/hex/native /opt/hex/native
ENV DEPENDABOT_NATIVE_HELPERS_PATH="/opt/hex/native"
ENV PATH="$PATH:/opt/hex/native/hex"
ENV HEX_CACERTS_PATH=/etc/ssl/certs/ca-certificates.crt

COPY --chown=dependabot:dependabot --parents hex common $DEPENDABOT_HOME/
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
