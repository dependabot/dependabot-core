FROM golang:1.22.0-bookworm as go

FROM ghcr.io/dependabot/dependabot-updater-core
ARG TARGETARCH

USER root

COPY --from=go /usr/local/go /opt/go

ENV PATH=/opt/go/bin:$PATH

ENV DEPENDABOT_NATIVE_HELPERS_PATH="/opt"

COPY go_modules/helpers /opt/go_modules/helpers
RUN bash /opt/go_modules/helpers/build

USER dependabot
COPY --chown=dependabot:dependabot go_modules $DEPENDABOT_HOME/go_modules
COPY --chown=dependabot:dependabot common $DEPENDABOT_HOME/common
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater

# See https://go.dev/doc/toolchain#select
# By specifying go1.20.10, we use 1.20.10 for any go.mod with go directive <= 1.20.
# In the file_parser, GOTOOLCHAIN=local is set otherwise, which uses the latest version above.
ENV GOTOOLCHAIN="go1.20.10"
# This pre-installs go 1.20 so that each job doesn't have to do it.
RUN go version
ENV GO_LEGACY=$GOTOOLCHAIN
