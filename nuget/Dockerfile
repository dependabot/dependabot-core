FROM ghcr.io/dependabot/dependabot-updater-core

USER dependabot

COPY --chown=dependabot:dependabot nuget $DEPENDABOT_HOME/nuget
COPY --chown=dependabot:dependabot common $DEPENDABOT_HOME/common
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater

### DOTNET
ENV DOTNET_NOLOGO=true \
  DOTNET_CLI_TELEMETRY_OPTOUT=true

RUN curl -sSL https://dot.net/v1/dotnet-install.sh | bash /dev/stdin --channel 7.0 --install-dir /usr/share/dotnet \
  && ln -s /usr/share/dotnet/dotnet /usr/bin/dotnet