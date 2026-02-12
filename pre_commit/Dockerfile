# syntax=docker.io/docker/dockerfile:1.20
FROM docker.io/library/golang:1.25.0-bookworm AS go

FROM ghcr.io/dependabot/dependabot-updater-core

USER root

COPY --from=go /usr/local/go /opt/go
ENV PATH=/opt/go/bin:$PATH

ENV DEPENDABOT_NATIVE_HELPERS_PATH="/opt"

COPY go_modules/helpers /opt/go_modules/helpers
RUN bash /opt/go_modules/helpers/build

USER dependabot

# TODO: If you have native helpers, uncomment and configure these lines:
# ENV DEPENDABOT_NATIVE_HELPERS_PATH="/opt"
# COPY --chown=dependabot:dependabot pre_commit/helpers /opt/pre_commit/helpers
# RUN bash /opt/pre_commit/helpers/build

COPY --chown=dependabot:dependabot --parents pre_commit common go_modules cargo npm_and_yarn python $DEPENDABOT_HOME/
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
