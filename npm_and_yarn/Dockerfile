FROM ghcr.io/dependabot/dependabot-updater-core
ENV DEPENDABOT_HOME /home/dependabot
### JAVASCRIPT

# Install Node and npm
RUN curl -sL https://deb.nodesource.com/setup_16.x | bash - \
  && apt-get update \
  && apt-get install -y --no-install-recommends \
  nodejs \
  && rm -rf /var/lib/apt/lists/* \
  && npm install -g npm@8.19.2 \
  && rm -rf ~/.npm

# Install yarn berry and set it to a stable version
RUN corepack enable \
  && corepack prepare yarn@3.2.3 --activate

USER dependabot
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

# Our native helpers pull in yarn 1, so we need to reset the version globally to
# 3.2.3.
RUN corepack prepare yarn@3.2.3 --activate

COPY --chown=dependabot:dependabot npm_and_yarn ${DEPENDABOT_HOME}/npm_and_yarn
