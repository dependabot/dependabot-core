FROM docker.io/library/golang:1.24.6-bookworm AS go

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

# Put binaries installed with `go install` in the PATH
ENV PATH=$DEPENDABOT_HOME/go/bin:$PATH

# Temporarily install https://go.dev/cl/657178 for new toolchain behavior.
# TODO: Switch to Go 1.25 when it is released.
RUN go install golang.org/dl/gotip@latest \
    && echo y | gotip download 657178 \
    && gotip version \
    && ln -sf "$(which gotip)" $DEPENDABOT_HOME/go/bin/go
