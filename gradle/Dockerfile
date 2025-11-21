# From https://hub.docker.com/_/gradle/tags
FROM gradle:8.14.3-jdk21-ubi-minimal AS gradle

FROM ghcr.io/dependabot/dependabot-updater-core

# Install Java
RUN apt-get update && apt-get install -y --no-install-recommends \
    openjdk-21-jdk \
    ca-certificates-java \
    && rm -rf /var/lib/apt/lists/*

# Install Gradle
ENV GRADLE_HOME=/opt/gradle
COPY --from=gradle $GRADLE_HOME $GRADLE_HOME
# Make the Gradle binary available system-wide
RUN ln -s "${GRADLE_HOME}/bin/gradle" /usr/bin/gradle

USER dependabot

ENV PATH=/usr/bin/gradle:$PATH

RUN set -o errexit -o nounset \
    && echo "Testing Gradle installation" \
    && gradle --version

COPY --chown=dependabot:dependabot maven $DEPENDABOT_HOME/maven
COPY --chown=dependabot:dependabot gradle $DEPENDABOT_HOME/gradle
COPY --chown=dependabot:dependabot common $DEPENDABOT_HOME/common
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
