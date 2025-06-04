FROM ghcr.io/dependabot/dependabot-updater-core

# Install Java
RUN apt-get update && apt-get install -y --no-install-recommends \
    openjdk-21-jdk \
    # avoids keytool usage
    ca-certificates-java \
    wget \
    # we need to allow the dependabot user to write to these files for when update-ca-certificates is run
    && chgrp dependabot /etc/default/cacerts  \
    && chmod g+rw /etc/default/cacerts \
    && chgrp dependabot /etc/ssl/certs/java/cacerts  \
    && chmod g+rw /etc/ssl/certs/java/cacerts \
    && rm -rf /var/lib/apt/lists/*

# Install Gradle
ENV GRADLE_HOME=/opt/gradle
ENV GRADLE_VERSION=8.14
ARG GRADLE_DOWNLOAD_SHA256=61ad310d3c7d3e5da131b76bbf22b5a4c0786e9d892dae8c1658d4b484de3caa
RUN set -o errexit -o nounset \
    && echo "Downloading Gradle" \
    && wget --no-verbose --output-document=gradle.zip "https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip" \
    \
    && echo "Checking Gradle download hash" \
    && echo "${GRADLE_DOWNLOAD_SHA256} *gradle.zip" | sha256sum -c - \
    \
    && echo "Installing Gradle" \
    && unzip gradle.zip \
    && rm gradle.zip \
    && mv "gradle-${GRADLE_VERSION}" "${GRADLE_HOME}/" \
    && ln -s "${GRADLE_HOME}/bin/gradle" /usr/bin/gradle

USER dependabot

ENV PATH=/usr/bin/gradle:$PATH

RUN set -o errexit -o nounset \
    && echo "Testing Gradle installation" \
    && gradle --version

COPY --chown=dependabot:dependabot maven $DEPENDABOT_HOME/maven
COPY --chown=dependabot:dependabot gradle $DEPENDABOT_HOME/gradle
COPY --chown=dependabot:dependabot common $DEPENDABOT_HOME/common
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
