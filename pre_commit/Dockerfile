# syntax=docker.io/docker/dockerfile:1.20
ARG UPDATER_CORE_IMAGE=ghcr.io/dependabot/dependabot-updater-core
ARG GO_MODULES_IMAGE=ghcr.io/dependabot/dependabot-updater-go_modules
ARG BUNDLER_IMAGE=ghcr.io/dependabot/dependabot-updater-bundler

FROM ${GO_MODULES_IMAGE} AS go_modules
FROM ${BUNDLER_IMAGE} AS bundler

FROM ${UPDATER_CORE_IMAGE}

USER root

# Copy Go installation and helpers from go_modules image
COPY --from=go_modules /opt/go /opt/go
COPY --from=go_modules /opt/go_modules /opt/go_modules
ENV PATH=/opt/go/bin:$PATH

ENV DEPENDABOT_NATIVE_HELPERS_PATH="/opt"

# Copy bundler helpers from bundler image (for Ruby additional_dependencies support)
COPY --from=bundler --chown=dependabot:dependabot /opt/bundler /opt/bundler

USER dependabot

COPY --chown=dependabot:dependabot --parents pre_commit common bundler go_modules cargo npm_and_yarn python $DEPENDABOT_HOME/
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
