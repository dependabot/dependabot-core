FROM ghcr.io/dependabot/dependabot-updater-core

# Check for updates at https://github.com/nodejs/corepack/releases
ARG COREPACK_VERSION=0.32.0

# Check for updates at https://github.com/pnpm/pnpm/releases
ARG PNPM_VERSION=9.15.5

# Check for updates at https://github.com/yarnpkg/berry/releases
ARG YARN_VERSION=4.5.3

# Check for updates at https://github.com/oven-sh/bun/releases
ARG BUN_VERSION=1.2.5

# See https://github.com/nodesource/distributions#installation-instructions
ARG NODEJS_VERSION=20

# Check for updates at https://github.com/npm/cli/releases
# This version should be compatible with the Node.js version declared above. See https://nodejs.org/en/download/releases as well
# TODO: Upgrade to 9.6.7 depending on the outcome of https://github.com/npm/cli/issues/6742
ARG NPM_VERSION=9.6.5

# Install Node and npm
RUN mkdir -p /etc/apt/keyrings \
  && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
  && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODEJS_VERSION}.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends \
  nodejs \
  && rm -rf /var/lib/apt/lists/* \
  && npm install -g corepack@$COREPACK_VERSION \
  && npm install -g corepack@$COREPACK_VERSION bun@$BUN_VERSION \
  && rm -rf ~/.npm

USER dependabot

# Install pnpm and set it to a stable version
RUN corepack install pnpm@$PNPM_VERSION --global

# Install yarn berry and set it to a stable version
RUN corepack install yarn@$YARN_VERSION --global

# Install npm and set it to a stable version
RUN corepack install npm@$NPM_VERSION --global

ENV DEPENDABOT_NATIVE_HELPERS_PATH="/opt"
COPY --chown=dependabot:dependabot bun/helpers /opt/bun/helpers
RUN bash /opt/bun/helpers/build

# START: HACKY WORKAROUND FOR NPM GIT INSTALLS SPAWNING CHILD PROCESS

# TODO: Remove these hacks once we've deprecated npm 6 support as it no longer
# spawns a child process to npm install git dependencies.

# Create the config file manually instead of using yarn/npm config set as this
# executes the package manager outputs to every job log
COPY --chown=dependabot:dependabot updater/config/.yarnrc updater/config/.npmrc $DEPENDABOT_HOME/

# For Yarn Berry we can set this via an environment variable
ENV NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt

# END: HACKY WORKAROUND FOR NPM GIT INSTALLS SPAWNING CHILD PROCESS

COPY --chown=dependabot:dependabot bun $DEPENDABOT_HOME/bun
COPY --chown=dependabot:dependabot common $DEPENDABOT_HOME/common
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
