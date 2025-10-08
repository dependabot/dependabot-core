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
# COPY --chown=dependabot:dependabot test_overwrite/helpers /opt/test_overwrite/helpers
# RUN bash /opt/test_overwrite/helpers/build

COPY --chown=dependabot:dependabot test_overwrite $DEPENDABOT_HOME/test_overwrite
COPY --chown=dependabot:dependabot common $DEPENDABOT_HOME/common
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
