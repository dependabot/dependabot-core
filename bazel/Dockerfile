# syntax=docker.io/docker/dockerfile:1.20
FROM ghcr.io/dependabot/dependabot-updater-core
ARG TARGETARCH

USER root

# Bazelisk version and checksums
# See https://github.com/bazelbuild/bazelisk/releases
ARG BAZELISK_VERSION=v1.27.0
# curl -sL https://github.com/bazelbuild/bazelisk/releases/download/${BAZELISK_VERSION}/bazelisk-linux-amd64 | sha256sum
ARG BAZELISK_AMD64_CHECKSUM=e1508323f347ad1465a887bc5d2bfb91cffc232d11e8e997b623227c6b32fb76
# curl -sL https://github.com/bazelbuild/bazelisk/releases/download/${BAZELISK_VERSION}/bazelisk-linux-arm64 | sha256sum
ARG BAZELISK_ARM64_CHECKSUM=bb608519a440d45d10304eb684a73a2b6bb7699c5b0e5434361661b25f113a5d

# Install Java, download and verify Bazelisk, configure certificates
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        openjdk-21-jdk-headless \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && update-ca-certificates \
    && curl -fsSL -o /usr/local/bin/bazelisk \
        "https://github.com/bazelbuild/bazelisk/releases/download/${BAZELISK_VERSION}/bazelisk-linux-${TARGETARCH}" \
    && case "${TARGETARCH}" in \
        amd64) echo "${BAZELISK_AMD64_CHECKSUM} /usr/local/bin/bazelisk" | sha256sum -c - ;; \
        arm64) echo "${BAZELISK_ARM64_CHECKSUM} /usr/local/bin/bazelisk" | sha256sum -c - ;; \
        *) echo "Unsupported architecture: ${TARGETARCH}" && exit 1 ;; \
       esac \
    && chmod +x /usr/local/bin/bazelisk \
    && ln -s /usr/local/bin/bazelisk /usr/local/bin/bazel \
    && echo "startup --host_jvm_args=-Djavax.net.ssl.trustStore=/etc/ssl/certs/java/cacerts" > /etc/bazel.bazelrc

USER dependabot

# Set standard SSL certificate environment variables
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    SSL_CERT_DIR=/etc/ssl/certs \
    BAZEL_SYSTEM_BAZELRC=/etc/bazel.bazelrc

COPY --chown=dependabot:dependabot --parents bazel common $DEPENDABOT_HOME/
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
