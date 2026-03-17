# syntax=docker.io/docker/dockerfile:1.20
FROM ghcr.io/dependabot/dependabot-updater-core

ARG MISE_VERSION=v2026.3.9
RUN curl -fsSL https://github.com/jdx/mise/releases/download/${MISE_VERSION}/install.sh \
    | MISE_INSTALL_PATH=/usr/local/bin/mise sh

USER dependabot

# required by mise's npm backend
RUN MISE_YES=1 mise use -g node@lts


COPY --chown=dependabot:dependabot --parents mise common $DEPENDABOT_HOME/
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
