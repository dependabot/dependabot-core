# syntax=docker.io/docker/dockerfile:1.20
FROM ghcr.io/dependabot/dependabot-updater-core

USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

USER dependabot

# Install Julia
RUN curl -fsSL https://install.julialang.org | sh -s -- -y \
    && . ~/.bashrc

ENV PATH="/home/dependabot/.juliaup/bin:$PATH"

ENV DEPENDABOT_NATIVE_HELPERS_PATH="/opt"
COPY --chown=dependabot:dependabot julia/helpers /opt/julia/helpers
RUN bash /opt/julia/helpers/build

# The Julia depot (~/.julia) is already in place from the build step above
# It contains precompiled packages, registries, and artifacts for fast startup

COPY --chown=dependabot:dependabot --parents julia common $DEPENDABOT_HOME/
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
