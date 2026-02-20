# syntax=docker.io/docker/dockerfile:1.20

# Import pre-built ecosystem images to avoid code duplication
# These images contain all the native helpers and tools already built
ARG GO_MODULES_BASE=ghcr.io/dependabot/dependabot-updater-gomod:latest
ARG BUNDLER_BASE=ghcr.io/dependabot/dependabot-updater-bundler:latest
ARG CORE_BASE=ghcr.io/dependabot/dependabot-updater-core:latest

FROM ${GO_MODULES_BASE} AS go_modules
FROM ${BUNDLER_BASE} AS bundler
FROM ${CORE_BASE}

USER root

# Copy Go installation and helpers from go_modules image
COPY --from=go_modules /opt/go /opt/go
COPY --from=go_modules /opt/go_modules /opt/go_modules
ENV PATH=/opt/go/bin:$PATH

ENV DEPENDABOT_NATIVE_HELPERS_PATH="/opt"

# Copy bundler helpers from bundler image (for Ruby additional_dependencies support)
COPY --from=bundler --chown=dependabot:dependabot /opt/bundler /opt/bundler

USER dependabot

COPY --chown=dependabot:dependabot --parents go_modules cargo npm_and_yarn python pre_commit common bundler $DEPENDABOT_HOME/
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
