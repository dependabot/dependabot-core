FROM ghcr.io/dependabot/dependabot-updater-core
ARG TARGETARCH

# Install regctl. See https://github.com/regclient/regclient/releases for updates
ARG REGCTL_VERSION=0.5.5

# These are manually calculated as they are not provided by the maintainer
# curl -sL https://github.com/regclient/regclient/releases/download/v${REGCTL_VERSION}/regctl-linux-amd64 | sha256sum
ARG REGCTL_AMD64_CHECKSUM=1ee329753045ccc74a2daf7f64c056390908d66a94ec5f1843f5967e80f66cff
# curl -sL https://github.com/regclient/regclient/releases/download/v${REGCTL_VERSION}/regctl-linux-arm64 | sha256sum
ARG REGCTL_ARM64_CHECKSUM=d734279b5955e2a2ab22ccf6080efaef03e2ca2edf3c8db7ad11a21f958c967f

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
