FROM ghcr.io/dependabot/dependabot-updater-core
ARG TARGETARCH

# See https://github.com/opentofu/opentofu/releases
ARG OPENTOFU_VERSION=1.10.6

# curl "https://github.com/opentofu/opentofu/releases/${OPENTOFU_VERSION}/tofu_${OPENTOFU_VERSION}_SHA256SUMS" | grep "tofu_${OPENTOFU_VERSION}_linux_amd64.zip"
ARG TOFU_AMD64_CHECKSUM=1eaed12ca41fcfe094da3d76a7e9aa0639ad3409c43be0103ee9f5a1ff4b7437

# curl "https://releases.hashicorp.com/terraform/${OPENTOFU_VERSION}/tofu_${OPENTOFU_VERSION}_SHA256SUMS" | grep "tofu_${OPENTOFU_VERSION}_linux_arm64.zip"
ARG TOFU_ARM64_CHECKSUM=f8a0347dc5e68e6d60a9fa2db361762e7943ed084a773f28a981d988ceb6fdc9


RUN cd /tmp \
  && curl -o tofu-${TARGETARCH}.tar.gz https://github.com/opentofu/opentofu/releases/download/v${OPENTOFU_VERSION}/tofu_${OPENTOFU_VERSION}_${TARGETARCH}.zip \
  && printf "$TOFU_AMD64_CHECKSUM tofu-amd64.tar.gz\n$TOFU_ARM64_CHECKSUM tofu-arm64.tar.gz\n" | sha256sum -c --ignore-missing - \
  && unzip -d /usr/local/bin tofu-${TARGETARCH}.tar.gz \
  && rm tofu-${TARGETARCH}.tar.gz

USER dependabot
COPY --chown=dependabot:dependabot opentofu/helpers /opt/opentofu/helpers
RUN bash /opt/opentofu/helpers/build

COPY --chown=dependabot:dependabot opentofu $DEPENDABOT_HOME/opentofu
COPY --chown=dependabot:dependabot common $DEPENDABOT_HOME/common
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
