# syntax=docker.io/docker/dockerfile:1.20
FROM ghcr.io/dependabot/dependabot-updater-core
ARG TARGETARCH

ENV PATH="${PATH}:/opt/swift/usr/bin"

# OS dependencies
# NOTE: Exclude i386 architecture to prevent apt from trying to install i386 variants
# that are unavailable in Ubuntu 26.04 (e.g., libxml2:i386). This doesn't impact arm64 builds.
RUN <<EOF
  mkdir -p /etc/apt/preferences.d
  echo -e 'Package: *:i386\nPin: release *\nPin-Priority: -1' > /etc/apt/preferences.d/exclude-i386
  apt-get update
  apt-get install -y --no-install-recommends \
    binutils \
    libc6-dev \
    libcurl4-openssl-dev \
    libedit2 \
    libgcc-13-dev \
    libncurses6 \
    libpython3-dev \
    libsqlite3-0 \
    libstdc++-13-dev \
    libxml2 \
    libncurses-dev \
    libz3-dev \
    pkg-config \
    tzdata \
    uuid-dev
  rm -rf /var/lib/apt/lists/*
EOF

USER dependabot

# https://www.swift.org/download/
# https://github.com/apple/swift-org-website/blob/main/_data/builds/swift_releases.yml
ARG SWIFT_VERSION=6.3.1
ARG SWIFT_UBUNTU_VERSION=ubuntu24.04
# NOTE: Pinned to Ubuntu 24.04 because Swift builds are not yet available for Ubuntu 26.04.
# See: https://github.com/swiftlang/swift/issues/88994
# To check if builds are available: curl -L -o /dev/null -w "%{http_code}" https://download.swift.org/swift-6.2.3-release/ubuntu2604/swift-6.2.3-RELEASE/swift-6.2.3-RELEASE-ubuntu26.04.tar.gz

RUN if [ "$TARGETARCH" = "arm64" ]; then SWIFT_UBUNTU_VERSION="${SWIFT_UBUNTU_VERSION}-aarch64"; fi \
  && SWIFT_SHORT_UBUNTU_VERSION=$(echo $SWIFT_UBUNTU_VERSION | tr -d .) \
  && SWIFT_TARBALL="swift-${SWIFT_VERSION}-RELEASE-${SWIFT_UBUNTU_VERSION}.tar.gz" \
  && SWIFT_SIGNATURE="${SWIFT_TARBALL}.sig" \
  && DOWNLOAD_URL=https://download.swift.org/swift-${SWIFT_VERSION}-release/${SWIFT_SHORT_UBUNTU_VERSION}/swift-${SWIFT_VERSION}-RELEASE/${SWIFT_TARBALL} \
  && curl --connect-timeout 15 --retry 5 "${DOWNLOAD_URL}" > "/tmp/${SWIFT_TARBALL}" \
  && curl --connect-timeout 15 --retry 5 "${DOWNLOAD_URL}.sig" > "/tmp/${SWIFT_SIGNATURE}" \
  && sh -c 'curl --location --compressed --connect-timeout 15 --retry 5 https://www.swift.org/keys/all-keys.asc | gpg --import -' \
  && gpg --keyserver hkp://keyserver.ubuntu.com --refresh-keys Swift \
  && gpg --verify /tmp/${SWIFT_SIGNATURE} \
  && mkdir /opt/swift \
  && tar -C /opt/swift -xzf /tmp/${SWIFT_TARBALL} --strip-components 1 \
  && rm -f /tmp/${SWIFT_TARBALL} /tmp/${SWIFT_SIGNATURE}

COPY --chown=dependabot:dependabot --parents swift common $DEPENDABOT_HOME/
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
