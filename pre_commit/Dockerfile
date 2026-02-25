# syntax=docker.io/docker/dockerfile:1.20

# Import pre-built ecosystem images to avoid code duplication
# These images contain all the native helpers and tools already built
FROM ghcr.io/dependabot/dependabot-updater-gomod:latest AS go_modules
FROM ghcr.io/dependabot/dependabot-updater-bundler:latest AS bundler

# Create an intermediate stage that combines both ecosystems into a single layer
FROM scratch AS combined-helpers
COPY --from=go_modules /opt/go /opt/go
COPY --from=go_modules /opt/go_modules /opt/go_modules
COPY --from=bundler /opt/bundler /opt/bundler

# Final stage - copy all helpers in a single layer from the combined stage
FROM ghcr.io/dependabot/dependabot-updater-core

USER root

# Copy all helpers from the combined intermediate stage (single layer)
COPY --from=combined-helpers --chown=dependabot:dependabot /opt /opt
ENV PATH=/opt/go/bin:$PATH

ENV DEPENDABOT_NATIVE_HELPERS_PATH="/opt"

USER dependabot

COPY --chown=dependabot:dependabot --parents go_modules cargo npm_and_yarn python pre_commit common bundler $DEPENDABOT_HOME/
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
