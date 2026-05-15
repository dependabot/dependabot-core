# syntax=docker.io/docker/dockerfile:1.20
ARG UPDATER_CORE_IMAGE=ghcr.io/dependabot/dependabot-updater-core
FROM ${UPDATER_CORE_IMAGE}

# This isn't a real ecosystem, adding it to make CI work easily.
# If you don't like this, it might be a good idea to move
# Dockerfile.updater-core in here instead, or refactor CI.

COPY --chown=dependabot:dependabot --parents common $DEPENDABOT_HOME/
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
