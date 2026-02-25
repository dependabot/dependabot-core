# syntax=docker.io/docker/dockerfile:1.20
FROM docker.io/library/golang:1.25.0-bookworm AS go

FROM ghcr.io/dependabot/dependabot-updater-core
ARG TARGETARCH

USER root

COPY --from=go /usr/local/go /opt/go
ENV PATH=/opt/go/bin:$PATH

ENV DEPENDABOT_NATIVE_HELPERS_PATH="/opt"

COPY go_modules/helpers /opt/go_modules/helpers
RUN bash /opt/go_modules/helpers/build

# Install Dart SDK for pub/dart additional_dependencies support
ENV PUB_CACHE=/opt/dart/pub-cache \
  PUB_ENVIRONMENT="dependabot" \
  PATH="${PATH}:/opt/dart/dart-sdk/bin"

# https://dart.dev/get-dart/archive
ARG DART_VERSION=3.10.0

RUN DART_ARCH=$(dpkg --print-architecture) \
  && if [ "$DART_ARCH" = "amd64" ]; then DART_ARCH=x64; fi \
  && DART_EXE="dartsdk-linux-${DART_ARCH}-release.zip" \
  && DOWNLOAD_URL="https://storage.googleapis.com/dart-archive/channels/stable/release/${DART_VERSION}/sdk/${DART_EXE}" \
  && curl --connect-timeout 15 --retry 5 "${DOWNLOAD_URL}" > "/tmp/${DART_EXE}" \
  && curl --connect-timeout 15 --retry 5 "${DOWNLOAD_URL}.sha256sum" > "/tmp/${DART_EXE}.sha256sum" \
  && cd /tmp/ \
  && echo "$(cat /tmp/${DART_EXE}.sha256sum)" | sha256sum -c \
  && mkdir -p "$PUB_CACHE" \
  && unzip "/tmp/${DART_EXE}" -d "/opt/dart" > /dev/null \
  && chmod -R o+rx "/opt/dart/dart-sdk" \
  && rm "/tmp/${DART_EXE}" \
  && dart --version

# Build pub helpers for dart additional_dependencies
COPY --chown=dependabot:dependabot pub/helpers /opt/pub/helpers
RUN bash /opt/pub/helpers/build

# Fix ownership of pub cache after helper build
RUN chown -R dependabot:dependabot "$PUB_CACHE"

USER dependabot

# Install bundler native helpers for Ruby additional_dependencies support
COPY --chown=dependabot:dependabot bundler/helpers /opt/bundler/helpers
RUN bash /opt/bundler/helpers/v2/build

COPY --chown=dependabot:dependabot --parents pre_commit common pub bundler go_modules cargo npm_and_yarn python $DEPENDABOT_HOME/
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
