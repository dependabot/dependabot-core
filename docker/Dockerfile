FROM ghcr.io/dependabot/dependabot-updater-core
ARG TARGETARCH

# Install regctl. See https://github.com/regclient/regclient/releases for updates
ARG REGCTL_VERSION=0.9.1

# These are manually calculated as they are not provided by the maintainer
# curl -sL https://github.com/regclient/regclient/releases/download/v${REGCTL_VERSION}/regctl-linux-amd64 | sha256sum
ARG REGCTL_AMD64_CHECKSUM=b32ba43ce2624fe09ebedbf3a5a5c8c4427eb9964b474b7ad75ed6b5f9a97d38
# curl -sL https://github.com/regclient/regclient/releases/download/v${REGCTL_VERSION}/regctl-linux-arm64 | sha256sum
ARG REGCTL_ARM64_CHECKSUM=1e37591c83e091391ceabae20154931dcb194ced52d8ac612521eab2cd255b8b

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
