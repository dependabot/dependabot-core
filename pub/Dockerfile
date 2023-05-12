FROM ghcr.io/dependabot/dependabot-updater-core
ARG TARGETARCH
# Install Dart
ENV PUB_CACHE=/opt/dart/pub-cache \
  PUB_ENVIRONMENT="dependabot" \
  PATH="${PATH}:/opt/dart/dart-sdk/bin"

# https://dart.dev/get-dart/archive
ARG DART_VERSION=2.19.0

RUN DART_ARCH=${TARGETARCH} \
  && if [ "$TARGETARCH" = "amd64" ]; then DART_ARCH=x64; fi \
  && DART_EXE="dartsdk-linux-${DART_ARCH}-release.zip" \
  && DOWNLOAD_URL="https://storage.googleapis.com/dart-archive/channels/stable/release/${DART_VERSION}/sdk/${DART_EXE}" \
  && curl --connect-timeout 15 --retry 5 "${DOWNLOAD_URL}" > "/tmp/${DART_EXE}" \
  && curl --connect-timeout 15 --retry 5 "${DOWNLOAD_URL}.sha256sum" > "/tmp/${DART_EXE}.sha256sum" \
  && cd /tmp/ \
  && echo "$(cat /tmp/${DART_EXE}.sha256sum)" | sha256sum -c \
  && mkdir -p "$PUB_CACHE" \
  && chown dependabot:dependabot "$PUB_CACHE" \
  && unzip "/tmp/${DART_EXE}" -d "/opt/dart" > /dev/null \
  && chmod -R o+rx "/opt/dart/dart-sdk" \
  && rm "/tmp/${DART_EXE}" \
  && dart --version

USER dependabot
COPY --chown=dependabot:dependabot pub/helpers /opt/pub/helpers
RUN bash /opt/pub/helpers/build

COPY --chown=dependabot:dependabot pub $DEPENDABOT_HOME/pub
COPY --chown=dependabot:dependabot common $DEPENDABOT_HOME/common
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
