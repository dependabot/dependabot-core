# syntax=docker.io/docker/dockerfile:1.20
FROM ghcr.io/dependabot/dependabot-updater-core

# Check for updates at https://github.com/nubjs/nub/releases
ARG NUB_VERSION=0.0.6

# See https://github.com/nodesource/distributions#installation-instructions
ARG NODEJS_VERSION=24

# Install Node and nub.
# nub is distributed as @nubjs/nub with per-platform binary optionalDependencies
# (@nubjs/nub-<platform>) placed by its postinstall; the container is linux-x64 (glibc).
RUN mkdir -p /etc/apt/keyrings \
  && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
  && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODEJS_VERSION}.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends \
  nodejs \
  && rm -rf /var/lib/apt/lists/* \
  && npm install -g @nubjs/nub@$NUB_VERSION \
  && rm -rf ~/.npm

USER dependabot

# Use our custom CA bundle.
ENV NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt

# Silence warning messages that aren't useful within the Dependabot context.
# These env vars are consumed by the Dependabot native helpers, which rely on npm/pnpm.
# CAUTION: `NPM_CONFIG_*` vars take precedence over the user's .npmrc settings. For these it always makes sense, but for
# other non-default configs it might be better to set them in a global .npmrc instead so users' .npmrc settings are respected.
ENV NPM_CONFIG_AUDIT=false \
    NPM_CONFIG_FUND=false

ENV DEPENDABOT_NATIVE_HELPERS_PATH="/opt"
COPY --chown=dependabot:dependabot nub/helpers /opt/nub/helpers
RUN bash /opt/nub/helpers/build

COPY --chown=dependabot:dependabot --parents nub common $DEPENDABOT_HOME/
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
