FROM ghcr.io/dependabot/dependabot-updater-core

# Check for updates at https://github.com/pnpm/pnpm/releases
ARG PNPM_VERSION=8.6.12

# Check for updates at https://github.com/yarnpkg/berry/releases
ARG YARN_VERSION=3.6.3

# See https://github.com/nodesource/distributions#installation-instructions
ARG NODEJS_VERSION=18.x

# Check for updates at https://github.com/npm/cli/releases
# This version should be compatible with the Node.js version declared above. See https://nodejs.org/en/download/releases as well
# TODO: Upgrade to 9.6.7 depending on the outcome of https://github.com/npm/cli/issues/6742
ARG NPM_VERSION=9.6.5

# Install Node and npm
RUN curl -sL https://deb.nodesource.com/setup_$NODEJS_VERSION | bash - \
  && apt-get update \
  && apt-get install -y --no-install-recommends \
  nodejs \
  && rm -rf /var/lib/apt/lists/* \
  && npm install -g npm@$NPM_VERSION \
  && rm -rf ~/.npm

RUN corepack enable

USER dependabot

# Install pnpm and set it to a stable version
RUN corepack prepare pnpm@$PNPM_VERSION --activate

# Install yarn berry and set it to a stable version
RUN corepack prepare yarn@$YARN_VERSION --activate

ENV DEPENDABOT_NATIVE_HELPERS_PATH="/opt"
COPY --chown=dependabot:dependabot npm_and_yarn/helpers /opt/npm_and_yarn/helpers
RUN bash /opt/npm_and_yarn/helpers/build

# START: HACKY WORKAROUND FOR NPM GIT INSTALLS SPAWNING CHILD PROCESS

# TODO: Remove these hacks once we've deprecated npm 6 support as it no longer
# spawns a child process to npm install git dependencies.

# Create the config file manually intead of using yarn/npm config set as this
# executes the package manager outputs to every job log
COPY --chown=dependabot:dependabot updater/config/.yarnrc updater/config/.npmrc $DEPENDABOT_HOME/

# For Yarn Berry we can set this via an environment variable
ENV NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt

# END: HACKY WORKAROUND FOR NPM GIT INSTALLS SPAWNING CHILD PROCESS

COPY --chown=dependabot:dependabot npm_and_yarn $DEPENDABOT_HOME/npm_and_yarn
COPY --chown=dependabot:dependabot common $DEPENDABOT_HOME/common
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
