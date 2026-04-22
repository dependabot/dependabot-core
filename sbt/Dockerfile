# syntax=docker.io/docker/dockerfile:1.20
FROM ghcr.io/dependabot/dependabot-updater-core

# TODO: Install any required dependencies for your ecosystem
# Example:
# RUN apt-get update \
#   && apt-get install -y --no-install-recommends \
#   your-package-manager \
#   && rm -rf /var/lib/apt/lists/*

USER dependabot

# TODO: If you have native helpers, uncomment and configure these lines:
# ENV DEPENDABOT_NATIVE_HELPERS_PATH="/opt"
# COPY --chown=dependabot:dependabot sbt/helpers /opt/sbt/helpers
# RUN bash /opt/sbt/helpers/build

COPY --chown=dependabot:dependabot --parents sbt common $DEPENDABOT_HOME/
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
