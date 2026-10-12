# syntax=docker.io/docker/dockerfile:1.20
FROM ghcr.io/dependabot/dependabot-updater-core

ARG TARGETARCH
ARG GH_ACTIONS_LOCK_VERSION=v0.1.6
ARG GH_ACTIONS_LOCK_AMD64_CHECKSUM=4181ec1da5408b34b9a542a7ee5c6ce3a4d6ac815c7d0206a00ceca8a817f4e3
ARG GH_ACTIONS_LOCK_ARM64_CHECKSUM=31c99e586f8f5fa2607ea79af74e3b50bc7ed4be1580a0d8449cdd73d1aba5e4

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
