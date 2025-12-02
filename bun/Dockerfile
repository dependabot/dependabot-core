# syntax=docker.io/docker/dockerfile:1.20
FROM ghcr.io/dependabot/dependabot-updater-core

# Check for updates at https://github.com/nodejs/corepack/releases
ARG COREPACK_VERSION=0.33.0

# Check for updates at https://github.com/oven-sh/bun/releases
ARG BUN_VERSION=1.2.5

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
ENV NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt

COPY --chown=dependabot:dependabot --parents bun common $DEPENDABOT_HOME/
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
