# syntax=docker.io/docker/dockerfile:1.20
# This cannot be inlined below (e.g., COPY --from=maven:...) because Dependabot does not support that syntax yet
FROM maven:3.9.9 as maven

FROM ghcr.io/dependabot/dependabot-updater-core AS builder

COPY --chown=dependabot:dependabot --from=maven /usr/share/maven $DEPENDABOT_HOME/maven-installation
COPY --chown=dependabot:dependabot --parents maven common $DEPENDABOT_HOME/
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater

FROM ghcr.io/dependabot/dependabot-updater-core

RUN apt-get update && apt-get install -y --no-install-recommends \
    openjdk-21-jdk-headless \
    ca-certificates-java \
    && rm -rf /var/lib/apt/lists/*

USER dependabot

COPY --from=builder $DEPENDABOT_HOME $DEPENDABOT_HOME

ENV MAVEN_HOME=$DEPENDABOT_HOME/maven-installation

ENV PATH="${JAVA_HOME}/bin:${MAVEN_HOME}/bin:${PATH}"

ENV MAVEN_ARGS="-Dmaven.repo.local=$DEPENDABOT_HOME/.m2"

# symlink so script/dependabot just works
RUN mkdir -p ~/.m2 && ln -s ~/maven/settings.xml ~/.m2/settings.xml
