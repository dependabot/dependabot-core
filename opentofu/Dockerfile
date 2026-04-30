# syntax=docker.io/docker/dockerfile:1.20
FROM ghcr.io/dependabot/dependabot-updater-core
ARG TARGETARCH

# See https://github.com/opentofu/opentofu/releases
ARG TOFU_VERSION=1.11.4
ARG ORAS_VERSION=1.3.0

# curl "https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}/tofu_${TOFU_VERSION}_SHA256SUMS" | grep "tofu_${TOFU_VERSION}_linux_amd64.zip"
ARG TOFU_AMD64_CHECKSUM=f3907e96b5a9f2fce311078ca273bcdf1e13980dac150b2549932c26b515c61b
ARG ORAS_AMD64_CHECKSUM=6cdc692f929100feb08aa8de584d02f7bcc30ec7d88bc2adc2054d782db57c64

# curl "https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}/tofu_${TOFU_VERSION}_SHA256SUMS" | grep "tofu_${TOFU_VERSION}_linux_arm64.zip"
ARG TOFU_ARM64_CHECKSUM=f877d46cb911d40bc0b81818d1940afdd356f632bcac48ca19dd8f7802a86701
ARG ORAS_ARM64_CHECKSUM=7649738b48fde10542bcc8b0e9b460ba83936c75fb5be01ee6d4443764a14352

RUN cd /tmp \
  && curl -L -o tofu-${TARGETARCH}.tar.gz https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}/tofu_${TOFU_VERSION}_linux_${TARGETARCH}.zip \
  && printf "$TOFU_AMD64_CHECKSUM tofu-amd64.tar.gz\n$TOFU_ARM64_CHECKSUM tofu-arm64.tar.gz\n" | sha256sum -c --ignore-missing - \
  && unzip -d /usr/local/bin tofu-${TARGETARCH}.tar.gz \
  && rm tofu-${TARGETARCH}.tar.gz

RUN cd /tmp \
  && curl -L -o oras-${TARGETARCH}.tar.gz https://github.com/oras-project/oras/releases/download/v${ORAS_VERSION}/oras_${ORAS_VERSION}_linux_${TARGETARCH}.tar.gz \
  && printf "$ORAS_AMD64_CHECKSUM oras-amd64.tar.gz\n$ORAS_ARM64_CHECKSUM oras-arm64.tar.gz\n" | sha256sum -c --ignore-missing - \
  && tar -xvzf oras-${TARGETARCH}.tar.gz -C /usr/local/bin/ \
  && rm oras-${TARGETARCH}.tar.gz

USER dependabot
COPY --chown=dependabot:dependabot opentofu/helpers /opt/opentofu/helpers
RUN bash /opt/opentofu/helpers/build

COPY --chown=dependabot:dependabot --parents opentofu common $DEPENDABOT_HOME/
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
