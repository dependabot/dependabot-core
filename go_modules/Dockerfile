FROM ghcr.io/dependabot/dependabot-updater-core
ARG TARGETARCH

USER root

# Install Go. See https://go.dev/dl/ for updates
ARG GOLANG_VERSION=1.21.1

# You can find the SHA's here: https://go.dev/dl/

# curl -s https://go.dev/dl/?mode=json | jq -r --arg GOLANG_VERSION "$GOLANG_VERSION" '.[] | .files[] | select(.filename == ("go" + $GOLANG_VERSION + ".linux-amd64.tar.gz")) | .sha256'
ARG GOLANG_AMD64_CHECKSUM=b3075ae1ce5dab85f89bc7905d1632de23ca196bd8336afd93fa97434cfa55ae

# curl -s https://go.dev/dl/?mode=json | jq -r --arg GOLANG_VERSION "$GOLANG_VERSION" '.[] | .files[] | select(.filename == ("go" + $GOLANG_VERSION + ".linux-arm64.tar.gz")) | .sha256'
ARG GOLANG_ARM64_CHECKSUM=7da1a3936a928fd0b2602ed4f3ef535b8cd1990f1503b8d3e1acc0fa0759c967

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
ENV GO_LEGACY=$GOTOOLCHAIN
