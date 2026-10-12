# syntax=docker.io/docker/dockerfile:1.20
FROM ghcr.io/dependabot/dependabot-updater-core

ARG TARGETARCH
ARG GH_ACTIONS_LOCK_VERSION=v0.2.0-rc.1
ARG GH_ACTIONS_LOCK_AMD64_CHECKSUM=51c52217c40e15b38454b7ad3ca9ac82368dc4bd4c82af5d1d1f1fd03619c2dd
ARG GH_ACTIONS_LOCK_ARM64_CHECKSUM=9aba8840bf00d4d64e9ded2ec96882a7284bd3cd92058969e03468f822e8c056

RUN mkdir -p /opt/github_actions/bin \
    && curl -fsSL -o /opt/github_actions/bin/gh-actions-lock \
      "https://github.com/github/gh-actions-lock/releases/download/${GH_ACTIONS_LOCK_VERSION}/linux-${TARGETARCH}" \
    && case "${TARGETARCH}" in \
      amd64) echo "${GH_ACTIONS_LOCK_AMD64_CHECKSUM} /opt/github_actions/bin/gh-actions-lock" | sha256sum -c - ;; \
      arm64) echo "${GH_ACTIONS_LOCK_ARM64_CHECKSUM} /opt/github_actions/bin/gh-actions-lock" | sha256sum -c - ;; \
      *) echo "Unsupported architecture: ${TARGETARCH}" && exit 1 ;; \
    esac \
    && chmod +x /opt/github_actions/bin/gh-actions-lock

USER dependabot

COPY --chown=dependabot:dependabot --parents github_actions common $DEPENDABOT_HOME/
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
