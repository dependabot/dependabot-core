FROM ghcr.io/dependabot/dependabot-updater-core
ARG TARGETARCH

USER root

# Install Go. See https://go.dev/dl/ for updates
ARG GOLANG_VERSION=1.20.6

# You can find the SHA's here: https://go.dev/dl/
ARG GOLANG_AMD64_CHECKSUM=b945ae2bb5db01a0fb4786afde64e6fbab50b67f6fa0eb6cfa4924f16a7ff1eb
ARG GOLANG_ARM64_CHECKSUM=4e15ab37556e979181a1a1cc60f6d796932223a0f5351d7c83768b356f84429b

ENV PATH=/opt/go/bin:$PATH
RUN cd /tmp \
  && curl --location --http1.1 -o go-${TARGETARCH}.tar.gz https://go.dev/dl/go${GOLANG_VERSION}.linux-${TARGETARCH}.tar.gz \
  && printf "$GOLANG_AMD64_CHECKSUM go-amd64.tar.gz\n$GOLANG_ARM64_CHECKSUM go-arm64.tar.gz\n" | sha256sum -c --ignore-missing - \
  && tar -xzf go-${TARGETARCH}.tar.gz -C /opt \
  && rm go-${TARGETARCH}.tar.gz

ENV DEPENDABOT_NATIVE_HELPERS_PATH="/opt"

COPY go_modules/helpers /opt/go_modules/helpers
RUN bash /opt/go_modules/helpers/build

USER dependabot
COPY --chown=dependabot:dependabot go_modules $DEPENDABOT_HOME/go_modules
COPY --chown=dependabot:dependabot common $DEPENDABOT_HOME/common
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
