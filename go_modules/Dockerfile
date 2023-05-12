FROM ghcr.io/dependabot/dependabot-updater-core
ARG TARGETARCH

USER root

# Install Go
ARG GOLANG_VERSION=1.20.4

# You can find the SHA's here: https://go.dev/dl/
ARG GOLANG_AMD64_CHECKSUM=698ef3243972a51ddb4028e4a1ac63dc6d60821bf18e59a807e051fee0a385bd
ARG GOLANG_ARM64_CHECKSUM=105889992ee4b1d40c7c108555222ca70ae43fccb42e20fbf1eebb822f5e72c6

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
