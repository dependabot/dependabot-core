FROM ghcr.io/dependabot/dependabot-updater-core

# Install VCPKG and dependencies
USER root
ARG VCPKG_VERSION=2025.06.13
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    cmake \
    ninja-build \
    zip \
    tar \
    pkg-config \
  && git clone https://github.com/microsoft/vcpkg.git /opt/vcpkg \
  && cd /opt/vcpkg \
  && git checkout $VCPKG_VERSION \
  && ./bootstrap-vcpkg.sh \
  && chown -R dependabot:dependabot /opt/vcpkg \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

USER dependabot

# Set VCPKG environment variables
ENV VCPKG_ROOT="/opt/vcpkg"
ENV PATH="/opt/vcpkg:$PATH"

COPY --chown=dependabot:dependabot vcpkg $DEPENDABOT_HOME/vcpkg
COPY --chown=dependabot:dependabot common $DEPENDABOT_HOME/common
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
