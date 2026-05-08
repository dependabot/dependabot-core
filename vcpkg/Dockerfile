# syntax=docker.io/docker/dockerfile:1.20
ARG UPDATER_CORE_IMAGE=ghcr.io/dependabot/dependabot-updater-core
FROM ${UPDATER_CORE_IMAGE}

# Install VCPKG and dependencies
USER root
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    cmake \
    ninja-build \
    zip \
    tar \
    pkg-config \
  && git clone https://github.com/microsoft/vcpkg.git /opt/vcpkg \
  && cd /opt/vcpkg \
  && ./bootstrap-vcpkg.sh \
  && chown -R dependabot:dependabot /opt/vcpkg \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

USER dependabot

# Set VCPKG environment variables
ENV VCPKG_ROOT="/opt/vcpkg"
ENV PATH="/opt/vcpkg:$PATH"

COPY --chown=dependabot:dependabot --parents vcpkg common $DEPENDABOT_HOME/
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
