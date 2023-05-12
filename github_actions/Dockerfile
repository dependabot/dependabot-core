FROM ghcr.io/dependabot/dependabot-updater-core

USER dependabot

COPY --chown=dependabot:dependabot github_actions $DEPENDABOT_HOME/github_actions
COPY --chown=dependabot:dependabot common $DEPENDABOT_HOME/common
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
