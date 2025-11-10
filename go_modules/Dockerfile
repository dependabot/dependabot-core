FROM docker.io/library/golang:1.25.4-bookworm AS go

FROM ghcr.io/dependabot/dependabot-updater-core
ARG TARGETARCH

USER root

COPY --from=go /usr/local/go /opt/go

ENV PATH=/opt/go/bin:$PATH

ENV DEPENDABOT_NATIVE_HELPERS_PATH="/opt"

COPY go_modules/helpers /opt/go_modules/helpers
# Copy mkcert CA certificate for GitHub Actions runners with HTTPS proxy
COPY go_modules/mkcert-ca.crt /usr/local/share/ca-certificates/mkcert-ca.crt
RUN update-ca-certificates && bash /opt/go_modules/helpers/build

USER dependabot
COPY --chown=dependabot:dependabot go_modules $DEPENDABOT_HOME/go_modules
COPY --chown=dependabot:dependabot common $DEPENDABOT_HOME/common
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
