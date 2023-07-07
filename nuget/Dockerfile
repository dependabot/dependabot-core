FROM ghcr.io/dependabot/dependabot-updater-core

USER root

# Set up the install directory
ENV DOTNET_HOME=/opt/dotnet \
  PATH="${PATH}:/opt/dotnet"
RUN mkdir -p "$DOTNET_HOME" && chown dependabot:dependabot "$DOTNET_HOME"

USER dependabot

ENV DOTNET_NOLOGO=true \
  DOTNET_CLI_TELEMETRY_OPTOUT=true

# Run dotnet without globalization support
ENV DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1

# Fetch and install dotnet
RUN curl -sSL https://dot.net/v1/dotnet-install.sh | bash /dev/stdin --channel 7.0 --install-dir /opt/dotnet

COPY --chown=dependabot:dependabot nuget $DEPENDABOT_HOME/nuget
COPY --chown=dependabot:dependabot common $DEPENDABOT_HOME/common
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater