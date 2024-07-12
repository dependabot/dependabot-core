FROM ghcr.io/dependabot/dependabot-updater-core
ARG TARGETARCH

ENV PATH="${PATH}:/opt/swift/usr/bin"

# OS dependencies
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    binutils \
    libc6-dev \
    libcurl4 \
    libedit2 \
    libgcc-9-dev \
    libpython3-dev \
    libsqlite3-0 \
    libstdc++-9-dev \
    libxml2 \
    libz3-dev \
    pkg-config \
    tzdata \
    uuid-dev \
  && rm -rf /var/lib/apt/lists/*

USER dependabot

# https://www.swift.org/download/
# https://github.com/apple/swift-org-website/blob/main/_data/builds/swift_releases.yml
ARG SWIFT_VERSION=5.10
ARG SWIFT_UBUNTU_VERSION=ubuntu22.04

RUN if [ "$TARGETARCH" = "arm64" ]; then SWIFT_UBUNTU_VERSION="${SWIFT_UBUNTU_VERSION}-aarch64"; fi \
  && SWIFT_SHORT_UBUNTU_VERSION=$(echo $SWIFT_UBUNTU_VERSION | tr -d .) \
  && SWIFT_TARBALL="swift-${SWIFT_VERSION}-RELEASE-${SWIFT_UBUNTU_VERSION}.tar.gz" \
  && SWIFT_SIGNATURE="${SWIFT_TARBALL}.sig" \
  && DOWNLOAD_URL=https://download.swift.org/swift-${SWIFT_VERSION}-release/${SWIFT_SHORT_UBUNTU_VERSION}/swift-${SWIFT_VERSION}-RELEASE/${SWIFT_TARBALL} \
  && curl --connect-timeout 15 --retry 5 "${DOWNLOAD_URL}" > "/tmp/${SWIFT_TARBALL}" \
  && curl --connect-timeout 15 --retry 5 "${DOWNLOAD_URL}.sig" > "/tmp/${SWIFT_SIGNATURE}" \
  && sh -c 'curl --connect-timeout 15 --retry 5 https://www.swift.org/keys/all-keys.asc | gpg --import -' \
  && gpg --keyserver hkp://keyserver.ubuntu.com --refresh-keys Swift \
  && gpg --verify /tmp/${SWIFT_SIGNATURE} \
  && mkdir /opt/swift \
  && tar -C /opt/swift -xzf /tmp/${SWIFT_TARBALL} --strip-components 1 \
  && rm -f /tmp/${SWIFT_TARBALL} /tmp/${SWIFT_SIGNATURE}

COPY --chown=dependabot:dependabot swift $DEPENDABOT_HOME/swift
COPY --chown=dependabot:dependabot common $DEPENDABOT_HOME/common
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
