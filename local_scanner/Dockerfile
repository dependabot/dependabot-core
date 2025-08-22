FROM ghcr.io/dependabot/dependabot-updater-core

USER dependabot

# Set up bundler helpers (required for bundler ecosystem)
COPY --chown=dependabot:dependabot bundler/helpers /opt/bundler/helpers
RUN bash /opt/bundler/helpers/v2/build

# Copy the local scanner files
COPY --chown=dependabot:dependabot local_scanner $DEPENDABOT_HOME/local_scanner
COPY --chown=dependabot:dependabot common $DEPENDABOT_HOME/common
COPY --chown=dependabot:dependabot bundler $DEPENDABOT_HOME/bundler
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
