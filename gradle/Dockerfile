# syntax=docker.io/docker/dockerfile:1.20
FROM gradle:8.14.3-jdk21-ubi-minimal@sha256:185ba366252215afd8717603017c7c69741d80adab138f382eb2c2d17227a6b3 AS gradle

FROM ghcr.io/dependabot/dependabot-updater-core AS builder

ENV GRADLE_HOME=/opt/gradle
COPY --from=gradle $GRADLE_HOME $DEPENDABOT_HOME/gradle-installation

COPY --chown=dependabot:dependabot --parents gradle maven common $DEPENDABOT_HOME
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater

FROM ghcr.io/dependabot/dependabot-updater-core

# Install Java
RUN apt-get update && apt-get install -y --no-install-recommends \
    openjdk-21-jdk-headless \
    ca-certificates-java \
    && rm -rf /var/lib/apt/lists/*

USER dependabot

ENV GRADLE_HOME=$DEPENDABOT_HOME/gradle-installation
ENV PATH=$GRADLE_HOME/bin:$PATH

COPY --from=builder $DEPENDABOT_HOME $DEPENDABOT_HOME

