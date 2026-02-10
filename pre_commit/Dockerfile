# syntax=docker.io/docker/dockerfile:1.20
FROM docker.io/library/golang:1.25.0-bookworm AS go

FROM ghcr.io/dependabot/dependabot-updater-core

# TODO: Install any required dependencies for your ecosystem
# Example:
# RUN apt-get update \
#   && apt-get install -y --no-install-recommends \
#   your-package-manager \
#   && rm -rf /var/lib/apt/lists/*

USER root

# Install Go for checking golang additional_dependencies
COPY --from=go /usr/local/go /opt/go
ENV PATH=/opt/go/bin:$PATH

ENV DEPENDABOT_NATIVE_HELPERS_PATH="/opt"

# Build Go native helpers
COPY go_modules/helpers /opt/go_modules/helpers
RUN bash /opt/go_modules/helpers/build

USER dependabot

COPY --chown=dependabot:dependabot --parents pre_commit common go_modules $DEPENDABOT_HOME/
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
