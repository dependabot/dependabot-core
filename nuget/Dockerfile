FROM ghcr.io/dependabot/dependabot-updater-core

USER root

ENV DEPENDABOT_NATIVE_HELPERS_PATH="/opt"

# install dependencies
RUN source /etc/os-release \
 && curl --location --output /tmp/packages-microsoft-prod.deb "https://packages.microsoft.com/config/ubuntu/$VERSION_ID/packages-microsoft-prod.deb" \
 && dpkg -i /tmp/packages-microsoft-prod.deb \
 && rm /tmp/packages-microsoft-prod.deb
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    jq \
    libicu-dev=70.1-2 \
    powershell \
 && rm -rf /var/lib/apt/lists/*

# Install .NET SDK
ARG DOTNET_LTS_SDK_VERSION=8.0.402
ARG DOTNET_STS_SDK_VERSION=9.0.100-rc.1.24452.12
ARG DOTNET_SDK_INSTALL_URL=https://dot.net/v1/dotnet-install.sh
ENV DOTNET_INSTALL_DIR=/usr/local/dotnet/current
ENV DOTNET_INSTALL_SCRIPT_PATH=/tmp/dotnet-install.sh
ENV DOTNET_NOLOGO=true
ENV DOTNET_ROOT="${DOTNET_INSTALL_DIR}"
ENV DOTNET_SKIP_FIRST_TIME_EXPERIENCE=true
ENV DOTNET_CLI_TELEMETRY_OPTOUT=true
ENV NUGET_SCRATCH=/opt/nuget/helpers/tmp

RUN curl --location --output "${DOTNET_INSTALL_SCRIPT_PATH}" "${DOTNET_SDK_INSTALL_URL}" \
 && chmod +x "${DOTNET_INSTALL_SCRIPT_PATH}" \
 && mkdir -p "${DOTNET_INSTALL_DIR}" \
 && "${DOTNET_INSTALL_SCRIPT_PATH}" --version "${DOTNET_LTS_SDK_VERSION}" --install-dir "${DOTNET_INSTALL_DIR}" \
 && "${DOTNET_INSTALL_SCRIPT_PATH}" --version "${DOTNET_STS_SDK_VERSION}" --install-dir "${DOTNET_INSTALL_DIR}" \
 && chown -R dependabot:dependabot "$DOTNET_INSTALL_DIR"
ENV PATH="${PATH}:${DOTNET_INSTALL_DIR}"
RUN dotnet --list-runtimes
RUN dotnet --list-sdks

# build tools
USER dependabot
COPY --chown=dependabot:dependabot nuget/helpers /opt/nuget/helpers
RUN bash /opt/nuget/helpers/build

COPY --chown=dependabot:dependabot nuget $DEPENDABOT_HOME/nuget
COPY --chown=dependabot:dependabot common $DEPENDABOT_HOME/common
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater

# redirect entrypoint
RUN mv bin/run bin/run-original
COPY --chown=dependabot:dependabot nuget/script/* $DEPENDABOT_HOME/dependabot-updater/bin/
COPY --chown=dependabot:dependabot nuget/updater/* $DEPENDABOT_HOME/dependabot-updater/bin/
RUN chmod +x $DEPENDABOT_HOME/dependabot-updater/bin/run
