FROM ghcr.io/dependabot/dependabot-updater-core
ARG TARGETARCH

# Install regctl
ARG REGCTL_VERSION=0.4.8
# These are manually calculated as they are not provided by the maintainer
ARG REGCTL_AMD64_CHECKSUM=89031da0802724505a73571c7bfa55bc57872147245d0d18bbc6123d7d4245b5
ARG REGCTL_ARM64_CHECKSUM=3973aeff35a7cd28a0a094e3d453fbc7aa230df9cdcffad9d1c44c85ec3192c9

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
