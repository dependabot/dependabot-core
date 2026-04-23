# syntax=docker.io/docker/dockerfile:1.20
FROM ghcr.io/dependabot/dependabot-updater-core
ARG TARGETARCH

# See https://github.com/opentofu/opentofu/releases
ARG TOFU_VERSION=1.11.4

# curl "https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}/tofu_${TOFU_VERSION}_SHA256SUMS" | grep "tofu_${TOFU_VERSION}_linux_amd64.zip"
ARG TOFU_AMD64_CHECKSUM=f3907e96b5a9f2fce311078ca273bcdf1e13980dac150b2549932c26b515c61b

# curl "https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}/tofu_${TOFU_VERSION}_SHA256SUMS" | grep "tofu_${TOFU_VERSION}_linux_arm64.zip"
ARG TOFU_ARM64_CHECKSUM=f877d46cb911d40bc0b81818d1940afdd356f632bcac48ca19dd8f7802a86701

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

COPY --chown=dependabot:dependabot --parents opentofu common $DEPENDABOT_HOME/
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
