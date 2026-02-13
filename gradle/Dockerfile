# syntax=docker.io/docker/dockerfile:1.20
# Dependabot should generally handle keeping the Gradle version up to date, though there may be situations where a manual update is required.
# When updating digests, always use the Multiplatform digest rather than one specific to a single architecture.
# Tools like `docker buildx imagetools` can help you locate the Multiplatform digest
# If you perform a manual update, make sure to update the tag as well.
# Including the tag with the digest is for documentation purposes, as Docker ignores the tag when a digest is provided
# It is useful because mapping tags to digests is challenging without OCI metadata, and many images do not provide this metadata.
FROM docker.io/gradle:9.0.0-jdk21-ubi-minimal@sha256:c20939c940c87862e811a843f81d1f62a5e2a08e5ce0638c4e606a3e8ac5dcdc AS gradle

FROM ghcr.io/dependabot/dependabot-updater-core

RUN apt-get update && apt-get install -y --no-install-recommends \
    openjdk-21-jdk-headless \
    ca-certificates-java \
    && rm -rf /var/lib/apt/lists/*

USER dependabot

# We do not need to persist GRADLE_HOME because Gradle does not use it
# See https://discuss.gradle.org/t/do-we-really-need-gradle-home-docs-site-inconsistency/21671/2
ARG GRADLE_HOME=/opt/gradle
ENV PATH=$GRADLE_HOME/bin:$PATH

COPY --from=gradle $GRADLE_HOME $GRADLE_HOME
COPY --chown=dependabot:dependabot --parents gradle maven common $DEPENDABOT_HOME/
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
