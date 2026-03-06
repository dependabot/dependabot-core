# syntax=docker.io/docker/dockerfile:1.20
FROM ghcr.io/dependabot/dependabot-updater-core

# Check for updates at https://github.com/nodejs/corepack/releases
ARG COREPACK_VERSION=0.33.0

# Check for updates at https://github.com/pnpm/pnpm/releases
# With every major release update, also update npm_and_yarn/lib/dependabot/npm_and_yarn/pnpm_package_manager.rb (Section : Update instructions)
ARG PNPM_VERSION=10.16.0

# Check for updates at https://github.com/yarnpkg/berry/releases
# With every major release update, also update npm_and_yarn/lib/dependabot/npm_and_yarn/yarn_package_manager.rb (Section : Update instructions)
ARG YARN_VERSION=4.9.2

# See https://github.com/nodesource/distributions#installation-instructions
# Always update NODEJS_VERSION with a compatible NPM_VERSION
# See https://nodejs.org/en/about/previous-releases#looking-for-the-latest-release-of-a-version-branch for more information
# Note : Always use the Active LTS version
ARG NODEJS_VERSION=24

# Check for updates at https://github.com/npm/cli/releases
# This version should be compatible with the NODEJS_VERSION version declared above. See https://nodejs.org/en/download/releases as well
# With every major release update, also update npm_and_yarn/lib/dependabot/npm_and_yarn/npm_package_manager.rb (Section : Update instructions)
ARG NPM_VERSION=11.7.0

# Install Node and npm
RUN mkdir -p /etc/apt/keyrings \
  && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
  && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODEJS_VERSION}.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends \
  nodejs \
  && rm -rf /var/lib/apt/lists/* \
  && npm install -g corepack@$COREPACK_VERSION \
  && rm -rf ~/.npm

USER dependabot

RUN <<EOF
  corepack install pnpm@$PNPM_VERSION --global
  corepack install yarn@$YARN_VERSION --global
  corepack install npm@$NPM_VERSION --global
  # Pre-cache popular older versions of npm for on-demand activation
  corepack install -g --cache-only npm@10 npm@9 npm@8
EOF

# Configure Node to use our custom CA bundle
ENV NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt

# Silence warning messages that aren't useful within the Dependabot context.
# CAUTION: `NPM_CONFIG_*` vars take precedence over the user's .npmrc settings. For these it always makes sense, but for
# other non-default configs it might be better to set them in a global .npmrc instead so users' .npmrc settings are respected.
ENV NPM_CONFIG_AUDIT=false \
    NPM_CONFIG_FUND=false

ENV DEPENDABOT_NATIVE_HELPERS_PATH="/opt"
COPY --chown=dependabot:dependabot npm_and_yarn/helpers /opt/npm_and_yarn/helpers
RUN bash /opt/npm_and_yarn/helpers/build

COPY --chown=dependabot:dependabot --parents npm_and_yarn common $DEPENDABOT_HOME/
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
