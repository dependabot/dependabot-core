# syntax=docker.io/docker/dockerfile:1.20
FROM ghcr.io/dependabot/dependabot-updater-core
ARG TARGETARCH

# See https://github.com/opentofu/opentofu/releases
ARG TOFU_VERSION=1.10.6

# curl "https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}/tofu_${TOFU_VERSION}_SHA256SUMS" | grep "tofu_${TOFU_VERSION}_linux_amd64.zip"
ARG TOFU_AMD64_CHECKSUM=15b7bed76420b50da3e121769c43341df8cd57d751ca14e6dbe9c850124c6dac

# curl "https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}/tofu_${TOFU_VERSION}_SHA256SUMS" | grep "tofu_${TOFU_VERSION}_linux_arm64.zip"
ARG TOFU_ARM64_CHECKSUM=a32f653d686a8cad9b9be82101eb5b5e834fbfa8d095842fa1820c5d27fad967


RUN cd /tmp \
  && curl -L -o tofu-${TARGETARCH}.tar.gz https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}/tofu_${TOFU_VERSION}_linux_${TARGETARCH}.zip \
  && printf "$TOFU_AMD64_CHECKSUM tofu-amd64.tar.gz\n$TOFU_ARM64_CHECKSUM tofu-arm64.tar.gz\n" | sha256sum -c --ignore-missing - \
  && unzip -d /usr/local/bin tofu-${TARGETARCH}.tar.gz \
  && rm tofu-${TARGETARCH}.tar.gz

USER dependabot
COPY --chown=dependabot:dependabot opentofu/helpers /opt/opentofu/helpers
RUN bash /opt/opentofu/helpers/build

COPY --chown=dependabot:dependabot --parents opentofu common $DEPENDABOT_HOME/
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
