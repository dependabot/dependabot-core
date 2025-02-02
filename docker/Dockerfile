FROM ghcr.io/dependabot/dependabot-updater-core
ARG TARGETARCH

# Install regctl. See https://github.com/regclient/regclient/releases for updates
ARG REGCTL_VERSION=0.5.6

# These are manually calculated as they are not provided by the maintainer
# curl -sL https://github.com/regclient/regclient/releases/download/v${REGCTL_VERSION}/regctl-linux-amd64 | sha256sum
ARG REGCTL_AMD64_CHECKSUM=ed352bc9991e3f12819b27fe516c58c4dab1fc0ee66c2f24d54c922a4f6fd582
# curl -sL https://github.com/regclient/regclient/releases/download/v${REGCTL_VERSION}/regctl-linux-arm64 | sha256sum
ARG REGCTL_ARM64_CHECKSUM=5e6ab7a5c48017f3213078ba726714010c608a7761f3f18e55d44be36ca5d95b

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
