# syntax=docker.io/docker/dockerfile:1.20
FROM ghcr.io/dependabot/dependabot-updater-core

USER dependabot

# Installs the APM CLI, which regenerates apm.lock.yaml
COPY --chown=dependabot:dependabot apm/helpers /opt/apm/helpers
RUN bash /opt/apm/helpers/build

COPY --chown=dependabot:dependabot --parents apm common $DEPENDABOT_HOME/
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
