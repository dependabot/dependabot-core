FROM ghcr.io/dependabot/dependabot-updater-core
ARG TARGETARCH

# OS dependencies
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    make \
    ca-certificates \
    gnupg \
    build-essential \
    curl \
  && mkdir -p /etc/apt/keyrings \
  && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
  && NODE_MAJOR=18 \
  && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list

RUN apt-get update -y \
  && apt-get install -y nodejs \
  && rm -rf /var/lib/apt/lists/*

RUN npm install -g @devcontainers/cli

USER dependabot

# Needed because tools like dependabot/cli will proxy/MITM the traffic
# to the registry with a cert that (without this change) is not known
# to the dev container process. See:
# * https://github.com/microsoft/vscode-remote-release/issues/6092
# * https://github.com/devcontainers/cli/blob/2d24543380dfc4d54e76b582536b52226af133c8/src/spec-utils/httpRequest.ts#L130-L162
# * https://github.com/devcontainers/cli/pull/559
ENV NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt

# Sanity check
RUN devcontainer --version

COPY --chown=dependabot:dependabot devcontainers $DEPENDABOT_HOME/devcontainers
COPY --chown=dependabot:dependabot common $DEPENDABOT_HOME/common
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
