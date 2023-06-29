FROM ghcr.io/dependabot/dependabot-updater-core

USER root

ENV DEPENDABOT_NATIVE_HELPERS_PATH="/opt"

# Install .NET SDK dependencies
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
  libicu-dev \
  && rm -rf /var/lib/apt/lists/*

# Install .NET SDK
ARG DOTNET_SDK_VERSION=7.0.305
ARG DOTNET_SDK_INSTALL_URL=https://dot.net/v1/dotnet-install.sh
ENV DOTNET_INSTALL_DIR="${DEPENDABOT_NATIVE_HELPERS_PATH}/dotnet"
ENV DOTNET_NOLOGO=true
ENV DOTNET_SKIP_FIRST_TIME_EXPERIENCE=true

RUN cd /tmp \
  && curl --location --output dotnet-install.sh "${DOTNET_SDK_INSTALL_URL}" \
  && chmod +x dotnet-install.sh \
  && mkdir -p "${DOTNET_INSTALL_DIR}" \
  && ./dotnet-install.sh --version "${DOTNET_SDK_VERSION}" --install-dir "${DOTNET_INSTALL_DIR}" \
  && rm dotnet-install.sh

ENV PATH="${PATH}:${DOTNET_INSTALL_DIR}"
RUN dotnet --list-sdks

COPY nuget/helpers /opt/nuget/helpers
RUN bash /opt/nuget/helpers/build

# ensure all users have access to the dotnet mutex paths
RUN chown -R dependabot:dependabot /tmp
RUN chmod 777 \
  /tmp \
  /tmp/.dotnet \
  /tmp/.dotnet/shm \
  /tmp/.dotnet/shm/session*

USER dependabot
COPY --chown=dependabot:dependabot nuget $DEPENDABOT_HOME/nuget
COPY --chown=dependabot:dependabot common $DEPENDABOT_HOME/common
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
