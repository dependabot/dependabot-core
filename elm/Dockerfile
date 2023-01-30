FROM ghcr.io/dependabot/dependabot-updater-core
ARG TARGETARCH
# Install Elm
# This is currently amd64 only, see:
# - https://github.com/elm/compiler/issues/2007
# - https://github.com/elm/compiler/issues/2232
ENV PATH="$PATH:/node_modules/.bin"
RUN [ "$TARGETARCH" != "amd64" ] \
  || (curl -sSLfO "https://github.com/elm/compiler/releases/download/0.19.0/binaries-for-linux.tar.gz" \
  && tar xzf binaries-for-linux.tar.gz \
  && mv elm /usr/local/bin/elm19 \
  && rm -f binaries-for-linux.tar.gz)

USER dependabot

COPY --chown=dependabot:dependabot elm /home/dependabot/elm
