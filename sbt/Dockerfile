# syntax=docker.io/docker/dockerfile:1.20
FROM ghcr.io/dependabot/dependabot-updater-core

# Install JDK for Coursier and Maven repository interaction
RUN apt-get update && apt-get install -y --no-install-recommends \
    openjdk-21-jdk-headless \
    ca-certificates-java \
    && rm -rf /var/lib/apt/lists/*

# Install Coursier native binary (v2.1.24)
# Coursier is SBT's built-in dependency resolver and understands Maven repos,
# Scala cross-versioning (%%), and SBT plugin repositories.
# Note: Coursier only publishes native Linux binaries for x86_64, which matches
# the dependabot-updater-core base image platform.
ARG COURSIER_VERSION=v2.1.24
RUN curl -fsSL "https://github.com/coursier/coursier/releases/download/${COURSIER_VERSION}/cs-x86_64-pc-linux.gz" \
      | gunzip > /usr/local/bin/cs && \
    chmod +x /usr/local/bin/cs

ENV DEPENDABOT_NATIVE_HELPERS_PATH="/opt"
COPY sbt/helpers /opt/sbt/helpers
RUN bash /opt/sbt/helpers/build

USER dependabot

COPY --chown=dependabot:dependabot --parents sbt maven common $DEPENDABOT_HOME/
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
