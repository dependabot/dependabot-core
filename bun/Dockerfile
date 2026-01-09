# syntax=docker.io/docker/dockerfile:1.20
FROM ghcr.io/dependabot/dependabot-updater-core

# Check for updates at https://github.com/nodejs/corepack/releases
ARG COREPACK_VERSION=0.33.0

# Check for updates at https://github.com/oven-sh/bun/releases
ARG BUN_VERSION=1.3.5

# See https://github.com/nodesource/distributions#installation-instructions
ARG NODEJS_VERSION=20

# Install Node and bun
RUN mkdir -p /etc/apt/keyrings \
  && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
  && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODEJS_VERSION}.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends \
  nodejs \
  && rm -rf /var/lib/apt/lists/* \
  && npm install -g corepack@$COREPACK_VERSION bun@$BUN_VERSION \
  && rm -rf ~/.npm

USER dependabot

# Configure Bun to use our custom CA bundle
# Even though Bun doesn't use Node, it respects this environment variable: https://bun.com/blog/bun-v1.1.22#node-extra-ca-certs
ENV NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt

# Silence warning messages that aren't useful within the Dependabot context.
# These env vars are not used by Bun directly, but only the Dependabot native helpers which currently rely on npm/yarn.
# CAUTION: `NPM_CONFIG_*` vars take precedence over the user's .npmrc settings. For these it always makes sense, but for
# other non-default configs it might be better to set them in a global .npmrc instead so users' .npmrc settings are respected.
ENV NPM_CONFIG_AUDIT=false \
    NPM_CONFIG_FUND=false

ENV DEPENDABOT_NATIVE_HELPERS_PATH="/opt"
COPY --chown=dependabot:dependabot bun/helpers /opt/bun/helpers
RUN bash /opt/bun/helpers/build

COPY --chown=dependabot:dependabot --parents bun common $DEPENDABOT_HOME/
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
