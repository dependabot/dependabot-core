# syntax=docker.io/docker/dockerfile:1.20
ARG UPDATER_CORE_IMAGE=ghcr.io/dependabot/dependabot-updater-core
ARG ELIXIR_VERSION=1.19.5
ARG ERLANG_VERSION=28.4.3
ARG UBUNTU_VERSION=noble-20260410

FROM hexpm/elixir:${ELIXIR_VERSION}-erlang-${ERLANG_VERSION}-ubuntu-${UBUNTU_VERSION} AS elixir-builder

# Install Zig (required by Burrito)
ARG ZIG_VERSION=0.15.2
ARG ZIG_CHECKSUM_X64=02aa270f183da276e5b5920b1dac44a63f1a49e55050ebde3aecc9eb82f93239
ARG ZIG_CHECKSUM_ARM64=958ed7d1e00d0ea76590d27666efbf7a932281b3d7ba0c6b01b0ff26498f667f
RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl xz-utils \
  && ARCH=$(uname -m) \
  && if [ "$ARCH" = "x86_64" ]; then ZIG_CHECKSUM="$ZIG_CHECKSUM_X64"; \
     elif [ "$ARCH" = "aarch64" ]; then ZIG_CHECKSUM="$ZIG_CHECKSUM_ARM64"; fi \
  && curl -sSLfO "https://ziglang.org/download/${ZIG_VERSION}/zig-${ARCH}-linux-${ZIG_VERSION}.tar.xz" \
  && echo "${ZIG_CHECKSUM}  zig-${ARCH}-linux-${ZIG_VERSION}.tar.xz" | sha256sum -c - \
  && tar -xf "zig-${ARCH}-linux-${ZIG_VERSION}.tar.xz" -C /usr/local \
  && ln -s "/usr/local/zig-${ARCH}-linux-${ZIG_VERSION}/zig" /usr/local/bin/zig \
  && rm "zig-${ARCH}-linux-${ZIG_VERSION}.tar.xz"

COPY hex/helpers /opt/hex/helpers
ENV MIX_HOME="/opt/hex/mix"
# https://github.com/hexpm/hex/releases
ENV HEX_VERSION="2.3.1"
ENV HEX_CACERTS_PATH=/etc/ssl/certs/ca-certificates.crt
ENV DEPENDABOT_NATIVE_HELPERS_PATH="/opt/hex/native"
RUN bash /opt/hex/helpers/build

FROM ${UPDATER_CORE_IMAGE}
COPY --from=elixir-builder /opt/hex/native /opt/hex/native
ENV DEPENDABOT_NATIVE_HELPERS_PATH="/opt/hex/native"
ENV PATH="$PATH:/opt/hex/native/hex"
ENV HEX_CACERTS_PATH=/etc/ssl/certs/ca-certificates.crt

# Pre-extract the Burrito payload so concurrent test runs don't race to extract
# it at runtime.
USER dependabot
RUN /opt/hex/native/hex/dependabot_hex --install
USER root

COPY --chown=dependabot:dependabot --parents hex common $DEPENDABOT_HOME/
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater