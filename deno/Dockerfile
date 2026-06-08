# syntax=docker.io/docker/dockerfile:1.20
ARG UPDATER_CORE_IMAGE=ghcr.io/dependabot/dependabot-updater-core
FROM ${UPDATER_CORE_IMAGE}

ARG DENO_VERSION=2.1.0

USER root

RUN curl -fsSL https://deno.land/install.sh | DENO_INSTALL=/usr/local sh -s v${DENO_VERSION}

USER dependabot

COPY --chown=dependabot:dependabot --parents deno common $DEPENDABOT_HOME/
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
