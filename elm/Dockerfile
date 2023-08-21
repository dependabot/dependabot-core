FROM ghcr.io/dependabot/dependabot-updater-core
ARG TARGETARCH
# Install Elm
# This is currently amd64 only, see:
# - https://github.com/elm/compiler/issues/2007
# - https://github.com/elm/compiler/issues/2232
ENV PATH="$PATH:/node_modules/.bin"
RUN [ "$TARGETARCH" != "amd64" ] \
  || (curl -sSLfO "https://github.com/elm/compiler/releases/download/0.19.1/binary-for-linux-64-bit.gz" \
  && gunzip binary-for-linux-64-bit.gz \
  && chmod o+x binary-for-linux-64-bit \
  && mv binary-for-linux-64-bit /usr/local/bin/elm19)

USER dependabot

COPY --chown=dependabot:dependabot elm $DEPENDABOT_HOME/elm
COPY --chown=dependabot:dependabot common $DEPENDABOT_HOME/common
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
