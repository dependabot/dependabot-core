FROM ghcr.io/dependabot/dependabot-updater-core
ARG TARGETARCH

# Install regctl. See https://github.com/regclient/regclient/releases for updates
ARG REGCTL_VERSION=0.5.0

# These are manually calculated as they are not provided by the maintainer
ARG REGCTL_AMD64_CHECKSUM=0378f7ed0a330ded959c8feea17f0bdc192fe8259e873a48f018b2259281c4f1
ARG REGCTL_ARM64_CHECKSUM=1a6274526eaab761edeb45b9bd696f57bc5a62b2eeeaec947ba4456c9afbd06b

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
