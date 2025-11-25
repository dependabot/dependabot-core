FROM ghcr.io/dependabot/dependabot-updater-core
ARG TARGETARCH

# See https://github.com/opentofu/opentofu/releases
ARG TOFU_VERSION=1.10.6

# curl "https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}/tofu_${TOFU_VERSION}_SHA256SUMS" | grep "tofu_${TOFU_VERSION}_linux_amd64.zip"
ARG TOFU_AMD64_CHECKSUM=15b7bed76420b50da3e121769c43341df8cd57d751ca14e6dbe9c850124c6dac

# curl "https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}/tofu_${TOFU_VERSION}_SHA256SUMS" | grep "tofu_${TOFU_VERSION}_linux_arm64.zip"
ARG TOFU_ARM64_CHECKSUM=a32f653d686a8cad9b9be82101eb5b5e834fbfa8d095842fa1820c5d27fad967

# Install tofu binary from Github releases
RUN cd /tmp \
  && curl -L -o tofu-${TARGETARCH}.tar.gz https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}/tofu_${TOFU_VERSION}_linux_${TARGETARCH}.zip \
  && printf "$TOFU_AMD64_CHECKSUM tofu-amd64.tar.gz\n$TOFU_ARM64_CHECKSUM tofu-arm64.tar.gz\n" | sha256sum -c --ignore-missing - \
  && unzip -d /usr/local/bin tofu-${TARGETARCH}.tar.gz \
  && rm tofu-${TARGETARCH}.tar.gz

# See https://github.com/minamijoyo/hcledit/releases
ARG HCLEDIT_VERSION=0.2.17

# curl -sL "https://github.com/minamijoyo/hcledit/releases/download/v${HCLEDIT_VERSION}/hcledit_${HCLEDIT_VERSION}_checksums.txt" | grep "hcledit_${HCLEDIT_VERSION}_linux_amd64.tar.gz"
ARG HCLEDIT_AMD64_CHECKSUM=5e085bd319c84c74e87b915ab2c1f95afccb2d4326be481fbe19c1d7a0eb5fee

# curl -sL "https://github.com/minamijoyo/hcledit/releases/download/v${HCLEDIT_VERSION}/hcledit_${HCLEDIT_VERSION}_checksums.txt" | grep "hcledit_${HCLEDIT_VERSION}_linux_arm64.tar.gz"
ARG HCLEDIT_ARM64_CHECKSUM=a1d052a5bbfd4c97c82946bd40097f61b5e7dbf7e43d39d52950633487b7bec4

# Install hcledit binary from Github releases
RUN cd /tmp \
  && curl -L -o hcledit-${TARGETARCH}.tar.gz https://github.com/minamijoyo/hcledit/releases/download/v${HCLEDIT_VERSION}/hcledit_${HCLEDIT_VERSION}_linux_${TARGETARCH}.tar.gz \
  && printf "$HCLEDIT_AMD64_CHECKSUM hcledit-amd64.tar.gz\n$HCLEDIT_ARM64_CHECKSUM hcledit-arm64.tar.gz\n" | sha256sum -c --ignore-missing - \
  && tar -xzf hcledit-${TARGETARCH}.tar.gz -C /usr/local/bin hcledit \
  && rm hcledit-${TARGETARCH}.tar.gz

USER dependabot
COPY --chown=dependabot:dependabot opentofu/helpers /opt/opentofu/helpers
RUN bash /opt/opentofu/helpers/build

COPY --chown=dependabot:dependabot opentofu $DEPENDABOT_HOME/opentofu
COPY --chown=dependabot:dependabot common $DEPENDABOT_HOME/common
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
