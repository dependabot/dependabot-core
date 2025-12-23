# syntax=docker.io/docker/dockerfile:1.20
# Dependabot should generally handle keeping the Gradle version up to date, though there may be situations where a manual update is required.
# When updating digests, always use the Multiplatform digest rather than one specific to a single architecture.
# Tools like `docker buildx imagetools` can help you locate the Multiplatform digest
# If you perform a manual update, make sure to update the tag as well.
# Including the tag with the digest is for documentation purposes, as Docker ignores the tag when a digest is provided
# It is useful because mapping tags to digests is challenging without OCI metadata, and many images or registries do not provide this metadata.
FROM docker.io/gradle:8.14.3-jdk21-ubi-minimal@sha256:185ba366252215afd8717603017c7c69741d80adab138f382eb2c2d17227a6b3 AS gradle

# By using dependabot-updater-core as the builder, we inherit $DEPENDABOT_HOME
# We also need to include it below for the final build, and using it as a builder should not negatively impact build time
FROM ghcr.io/dependabot/dependabot-updater-core AS builder

# Copying all files from `$DEPENDABOT_HOME` with a builder consolidates the final copy into a single Docker layer
COPY --from=gradle /opt/gradle $DEPENDABOT_HOME/gradle-installation

COPY --chown=dependabot:dependabot --parents gradle maven common $DEPENDABOT_HOME
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater

FROM ghcr.io/dependabot/dependabot-updater-core

RUN apt-get update && apt-get install -y --no-install-recommends \
    openjdk-21-jdk-headless \
    ca-certificates-java \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

USER dependabot

# We do not need to persist GRADLE_HOME because Gradle does not use it
# See https://discuss.gradle.org/t/do-we-really-need-gradle-home-docs-site-inconsistency/21671/2
ARG GRADLE_HOME=$DEPENDABOT_HOME/gradle-installation
ENV PATH=$GRADLE_HOME/bin:$PATH

COPY --from=builder $DEPENDABOT_HOME $DEPENDABOT_HOME

