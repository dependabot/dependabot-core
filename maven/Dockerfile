FROM ghcr.io/dependabot/dependabot-updater-core

RUN apt-get update && apt-get install -y --no-install-recommends \
    openjdk-21-jdk \
    # avoids keytool usage
    ca-certificates-java \
    # we need to allow the dependabot user to write to these files for when update-ca-certificates is run
    && chgrp dependabot /etc/default/cacerts  \
    && chmod g+rw /etc/default/cacerts \
    && chgrp dependabot /etc/ssl/certs/java/cacerts  \
    && chmod g+rw /etc/ssl/certs/java/cacerts \
    && rm -rf /var/lib/apt/lists/*

COPY --from=maven:3.9.9 /usr/share/maven /usr/share/maven

ENV MAVEN_HOME=/usr/share/maven

RUN ln -s ${MAVEN_HOME}/bin/mvn /usr/bin/mvn

USER dependabot

ENV PATH=$JAVA_HOME/bin:$PATH
ENV MAVEN_CONFIG "$DEPENDABOT_HOME/.m2"

COPY --chown=dependabot:dependabot maven $DEPENDABOT_HOME/maven
COPY --chown=dependabot:dependabot common $DEPENDABOT_HOME/common
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater

# symlink so script/dependabot just works
RUN mkdir -p ~/.m2 && ln -s ~/maven/settings.xml ~/.m2/settings.xml
