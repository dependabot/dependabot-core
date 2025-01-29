FROM ghcr.io/dependabot/dependabot-updater-core

USER dependabot

COPY --chown=dependabot:dependabot maven $DEPENDABOT_HOME/maven
COPY --chown=dependabot:dependabot gradle $DEPENDABOT_HOME/gradle
COPY --chown=dependabot:dependabot common $DEPENDABOT_HOME/common
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
