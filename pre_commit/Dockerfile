# syntax=docker.io/docker/dockerfile:1.20

# Import pre-built ecosystem images to avoid code duplication
# These images contain all the native helpers and tools already built
ARG UPDATER_CORE_IMAGE=ghcr.io/dependabot/dependabot-updater-core
ARG UPDATER_GOMOD_IMAGE=ghcr.io/dependabot/dependabot-updater-gomod:latest
ARG UPDATER_BUNDLER_IMAGE=ghcr.io/dependabot/dependabot-updater-bundler:latest
ARG UPDATER_PUB_IMAGE=ghcr.io/dependabot/dependabot-updater-pub:latest
FROM ${UPDATER_GOMOD_IMAGE} AS go_modules
FROM ${UPDATER_BUNDLER_IMAGE} AS bundler
FROM ${UPDATER_PUB_IMAGE} AS pub

# Create an intermediate stage that combines both ecosystems into a single layer
FROM scratch AS combined-helpers
COPY --from=go_modules /opt/go /opt/go
COPY --from=go_modules /opt/go_modules /opt/go_modules
COPY --from=bundler /opt/bundler /opt/bundler
COPY --from=pub /opt/dart /opt/dart
COPY --from=pub /opt/pub /opt/pub

# Final stage - copy all helpers in a single layer from the combined stage
FROM ${UPDATER_CORE_IMAGE}

USER root

# Copy all helpers from the combined intermediate stage (single layer)
COPY --from=combined-helpers --chown=dependabot:dependabot /opt /opt
ENV PATH=/opt/go/bin:/opt/dart/dart-sdk/bin:$PATH

ENV DEPENDABOT_NATIVE_HELPERS_PATH="/opt"

# Set up Dart/pub environment
ENV PUB_CACHE=/opt/dart/pub-cache \
  PUB_ENVIRONMENT="dependabot"

USER dependabot

COPY --chown=dependabot:dependabot --parents go_modules cargo npm_and_yarn python pre_commit common bundler pub $DEPENDABOT_HOME/
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
