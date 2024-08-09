FROM ghcr.io/dependabot/dependabot-updater-core

USER root

ENV DEPENDABOT_NATIVE_HELPERS_PATH="/opt"

# Install .NET SDK dependencies
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
  libicu-dev=70.1-2 \
  && rm -rf /var/lib/apt/lists/*

# Install .NET SDK
ARG DOTNET_SDK_VERSION=8.0.303
ARG DOTNET_SDK_INSTALL_URL=https://dot.net/v1/dotnet-install.sh
ENV DOTNET_INSTALL_DIR=/usr/local/dotnet/current
ENV DOTNET_NOLOGO=true
ENV DOTNET_ROOT="${DOTNET_INSTALL_DIR}"
ENV DOTNET_SKIP_FIRST_TIME_EXPERIENCE=true
ENV DOTNET_CLI_TELEMETRY_OPTOUT=true
ENV NUGET_SCRATCH=/opt/nuget/helpers/tmp

RUN cd /tmp \
  && curl --location --output dotnet-install.sh "${DOTNET_SDK_INSTALL_URL}" \
  && chmod +x dotnet-install.sh \
  && mkdir -p "${DOTNET_INSTALL_DIR}" \
  && ./dotnet-install.sh --version "${DOTNET_SDK_VERSION}" --install-dir "${DOTNET_INSTALL_DIR}" \
  && rm dotnet-install.sh \
  && chown -R dependabot:dependabot "${DOTNET_INSTALL_DIR}/sdk"

ENV PATH="${PATH}:${DOTNET_INSTALL_DIR}"
RUN dotnet --list-runtimes
RUN dotnet --list-sdks

USER dependabot
COPY --chown=dependabot:dependabot nuget/helpers /opt/nuget/helpers
RUN bash /opt/nuget/helpers/build

COPY --chown=dependabot:dependabot nuget $DEPENDABOT_HOME/nuget
COPY --chown=dependabot:dependabot common $DEPENDABOT_HOME/common
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
