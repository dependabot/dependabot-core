FROM ghcr.io/dependabot/dependabot-updater-core

ARG TARGETARCH

USER root

ENV DEPENDABOT_NATIVE_HELPERS_PATH="/opt"

# install dependencies
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    jq \
    libicu-dev=70.1-2 \
 && rm -rf /var/lib/apt/lists/*

# install libssl 1.0 for .NET 2.0
ARG LIBSSL10_URL_AMD64=http://security.ubuntu.com/ubuntu/pool/main/o/openssl1.0/libssl1.0.0_1.0.2n-1ubuntu5.13_amd64.deb
ARG LIBSSL10_URL_ARM64=http://ports.ubuntu.com/pool/main/o/openssl1.0/libssl1.0.0_1.0.2n-1ubuntu5.13_arm64.deb
RUN URL=$([ $TARGETARCH = "arm64" ] && echo ${LIBSSL10_URL_ARM64} || echo ${LIBSSL10_URL_AMD64}) \
 && curl --location --output /tmp/libssl-1.0.deb ${URL} \
 && dpkg -i /tmp/libssl-1.0.deb \
 && rm /tmp/libssl-1.0.deb

# install libssl 1.1 for .NET 3.0 through 5.0
ARG LIBSSL11_URL_AMD64=http://security.ubuntu.com/ubuntu/pool/main/o/openssl/libssl1.1_1.1.1f-1ubuntu2.24_amd64.deb
ARG LIBSSL11_URL_ARM64=http://ports.ubuntu.com/pool/main/o/openssl/libssl1.1_1.1.1f-1ubuntu2.24_arm64.deb
RUN URL=$([ $TARGETARCH = "arm64" ] && echo ${LIBSSL11_URL_ARM64} || echo ${LIBSSL11_URL_AMD64}) \
 && curl --location --output /tmp/libssl-1.1.deb ${URL} \
 && dpkg -i /tmp/libssl-1.1.deb \
 && rm /tmp/libssl-1.1.deb

ARG POWERSHELL_VERSION=7.4.5
RUN ARCH=$([ $TARGETARCH = "arm64" ] && echo "arm64" || echo "x64") \
 && POWERSHELL_VERSION_MAJOR=$(echo $POWERSHELL_VERSION | cut -d. -f1) \
 && INSTALL_PATH=/usr/local/microsoft/powershell/${POWERSHELL_VERSION_MAJOR} \
 && curl --location --output /tmp/powershell.tar.gz "https://github.com/PowerShell/PowerShell/releases/download/v${POWERSHELL_VERSION}/powershell-${POWERSHELL_VERSION}-linux-${ARCH}.tar.gz" \
 && mkdir -p $INSTALL_PATH \
 && tar zxf /tmp/powershell.tar.gz -C $INSTALL_PATH \
 && chmod +x $INSTALL_PATH/pwsh \
 && ln -s $INSTALL_PATH/pwsh /usr/bin/pwsh \
 && rm /tmp/powershell.tar.gz \
 && pwsh --version

# Install .NET SDK
ARG DOTNET_LTS_SDK_VERSION=8.0.404
ARG DOTNET_STS_SDK_VERSION=9.0.101
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

# ensure windows-style environment variables are set
ARG TEMP_DIR=/tmp/dependabot
RUN mkdir -p $TEMP_DIR
ENV TEMP=$TEMP_DIR
ENV TMP=$TEMP_DIR

# redirect entrypoint
RUN mv bin/run bin/run-original
COPY --chown=dependabot:dependabot nuget/script/* $DEPENDABOT_HOME/dependabot-updater/bin/
COPY --chown=dependabot:dependabot nuget/updater/* $DEPENDABOT_HOME/dependabot-updater/bin/
RUN chmod +x $DEPENDABOT_HOME/dependabot-updater/bin/run

# .NET install targeting packs
RUN pwsh $DEPENDABOT_HOME/dependabot-updater/bin/install-targeting-packs.ps1
