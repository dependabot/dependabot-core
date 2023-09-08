FROM ghcr.io/dependabot/dependabot-updater-core
ARG TARGETARCH

USER root

# Install Go. See https://go.dev/dl/ for updates
ARG GOLANG_VERSION=1.21.0

# You can find the SHA's here: https://go.dev/dl/
ARG GOLANG_AMD64_CHECKSUM=d0398903a16ba2232b389fb31032ddf57cac34efda306a0eebac34f0965a0742
ARG GOLANG_ARM64_CHECKSUM=f3d4548edf9b22f26bbd49720350bbfe59d75b7090a1a2bff1afad8214febaf3

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

# See https://go.dev/doc/toolchain#select
# By specifying go1.20.8, we use 1.20.8 for any go.mod with go directive <= 1.20.
# In the file_parser, GOTOOLCHAIN=local is set otherwise, which uses the latest version above.
ENV GOTOOLCHAIN="go1.20.8"
# This pre-installs go 1.20.8 so that each job doesn't have to do it.
RUN go version
