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

# Add Helm installation
ARG HELM_VERSION=3.17.2
# Checksums for Helm
# curl -sL https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz | sha256sum
ARG HELM_AMD64_CHECKSUM=90c28792a1eb5fb0b50028e39ebf826531ebfcf73f599050dbd79bab2f277241
# curl -sL https://get.helm.sh/helm-v${HELM_VERSION}-linux-arm64.tar.gz | sha256sum
ARG HELM_ARM64_CHECKSUM=0b13ec8580dd5498b5a2d7cb34146e098049f59500a266db1bb98f59649eb90a

ENV PATH=/opt/bin:$PATH
RUN cd /tmp \
  && curl -sSf -o regctl-${TARGETARCH} -L https://github.com/regclient/regclient/releases/download/v${REGCTL_VERSION}/regctl-linux-${TARGETARCH} \
  && printf "$REGCTL_AMD64_CHECKSUM regctl-amd64\n$REGCTL_ARM64_CHECKSUM regctl-arm64\n" | sha256sum -c --ignore-missing - \
  && mkdir -p /opt/bin \
  && mv regctl-${TARGETARCH} /opt/bin/regctl \
  && chmod o+rx /opt/bin/regctl \
  # Install Helm
  && curl -sSf -L https://get.helm.sh/helm-v${HELM_VERSION}-linux-${TARGETARCH}.tar.gz | tar xz \
  && mv linux-${TARGETARCH}/helm /opt/bin/helm \
  && chmod o+rx /opt/bin/helm \
  && rm -rf linux-${TARGETARCH}

USER dependabot

COPY --chown=dependabot:dependabot helm $DEPENDABOT_HOME/helm
COPY --chown=dependabot:dependabot common $DEPENDABOT_HOME/common
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
COPY --chown=dependabot:dependabot docker $DEPENDABOT_HOME/docker
