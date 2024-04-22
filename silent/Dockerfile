FROM ghcr.io/dependabot/dependabot-updater-core

USER dependabot

COPY --chown=dependabot:dependabot silent $DEPENDABOT_HOME/silent
COPY --chown=dependabot:dependabot common $DEPENDABOT_HOME/common
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
