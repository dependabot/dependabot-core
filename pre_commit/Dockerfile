# syntax=docker.io/docker/dockerfile:1.20
FROM docker.io/library/golang:1.25.0-bookworm AS go

FROM ghcr.io/dependabot/dependabot-updater-core

USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

USER dependabot

# Install Julia (required for Julia additional_dependency version lookups)
RUN curl -fsSL https://install.julialang.org | sh -s -- -y \
    && . ~/.bashrc

ENV PATH="/home/dependabot/.juliaup/bin:$PATH"
ENV JULIA_PKG_SERVER_REGISTRY_PREFERENCE="eager"

# Build Julia native helpers
ENV DEPENDABOT_NATIVE_HELPERS_PATH="/opt"
COPY --chown=dependabot:dependabot julia/helpers /opt/julia/helpers
RUN bash /opt/julia/helpers/build

COPY --chown=dependabot:dependabot --parents go_modules cargo npm_and_yarn python julia pre_commit common bundler $DEPENDABOT_HOME/
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
