# syntax=docker.io/docker/dockerfile:1.20
FROM ghcr.io/dependabot/dependabot-updater-core

# Install jq for JSON processing in native helpers
USER root
RUN apt-get update && apt-get install -y --no-install-recommends jq curl \
    && rm -rf /var/lib/apt/lists/*

USER dependabot

# Install elan (Lean version manager)
RUN curl https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh -sSf | sh -s -- -y --default-toolchain none
ENV PATH="/home/dependabot/.elan/bin:${PATH}"

COPY --chown=dependabot:dependabot --parents lean common $DEPENDABOT_HOME/

# Build native helpers
ENV DEPENDABOT_NATIVE_HELPERS_PATH="/opt/dependabot/helpers"
RUN mkdir -p $DEPENDABOT_NATIVE_HELPERS_PATH/lean \
    && cp -r $DEPENDABOT_HOME/lean/helpers/* $DEPENDABOT_NATIVE_HELPERS_PATH/lean/ \
    && chmod +x $DEPENDABOT_NATIVE_HELPERS_PATH/lean/run.sh \
    && chmod +x $DEPENDABOT_NATIVE_HELPERS_PATH/lean/build

COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
