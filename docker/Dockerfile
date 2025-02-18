FROM ghcr.io/dependabot/dependabot-updater-core
ARG TARGETARCH

# Install regctl. See https://github.com/regclient/regclient/releases for updates
ARG REGCTL_VERSION=0.8.2

# These are manually calculated as they are not provided by the maintainer
# curl -sL https://github.com/regclient/regclient/releases/download/v${REGCTL_VERSION}/regctl-linux-amd64 | sha256sum
ARG REGCTL_AMD64_CHECKSUM=0019dfc4b32d63c1392aa264aed2253c1e0c2fb09216f8e2cc269bbfb8bb49b5
# curl -sL https://github.com/regclient/regclient/releases/download/v${REGCTL_VERSION}/regctl-linux-arm64 | sha256sum
ARG REGCTL_ARM64_CHECKSUM=0019dfc4b32d63c1392aa264aed2253c1e0c2fb09216f8e2cc269bbfb8bb49b5

ENV PATH=/opt/bin:$PATH
RUN cd /tmp \
  && curl -sSf -o regctl-${TARGETARCH} -L https://github.com/regclient/regclient/releases/download/v${REGCTL_VERSION}/regctl-linux-${TARGETARCH} \
  && printf "$REGCTL_AMD64_CHECKSUM regctl-amd64\n$REGCTL_ARM64_CHECKSUM regctl-arm64\n" | sha256sum -c --ignore-missing - \
  && mkdir /opt/bin \
  && mv regctl-${TARGETARCH} /opt/bin/regctl \
  && chmod o+rx /opt/bin/regctl

USER dependabot

COPY --chown=dependabot:dependabot docker $DEPENDABOT_HOME/docker
COPY --chown=dependabot:dependabot common $DEPENDABOT_HOME/common
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
