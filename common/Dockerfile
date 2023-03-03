FROM ghcr.io/dependabot/dependabot-updater-core

# This isn't a real ecosystem, adding it to make CI work easily.
# If you don't like this, it might be a good idea to move
# Dockerfile.updater-core in here instead, or refactor CI.

COPY --chown=dependabot:dependabot common $DEPENDABOT_HOME/common
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
