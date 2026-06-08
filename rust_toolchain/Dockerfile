# syntax=docker.io/docker/dockerfile:1.20
ARG UPDATER_CORE_IMAGE=ghcr.io/dependabot/dependabot-updater-core
FROM ${UPDATER_CORE_IMAGE}

USER dependabot

COPY --chown=dependabot:dependabot --parents rust_toolchain common $DEPENDABOT_HOME/
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
