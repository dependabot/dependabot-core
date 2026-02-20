# syntax=docker.io/docker/dockerfile:1.20

# Import pre-built ecosystem images to avoid code duplication
# These images contain all the native helpers and tools already built
FROM ghcr.io/dependabot/dependabot-updater-gomod AS go_modules
FROM ghcr.io/dependabot/dependabot-updater-bundler AS bundler

FROM ghcr.io/dependabot/dependabot-updater-core

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
