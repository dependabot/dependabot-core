# syntax=docker.io/docker/dockerfile:1.20
FROM ghcr.io/dependabot/dependabot-updater-core

ARG TARGETARCH
ARG GH_ACTIONS_LOCK_VERSION=v0.2.0
ARG GH_ACTIONS_LOCK_AMD64_CHECKSUM=79ec84c191667fd935a277e6fd3662cf5d3669cccc9e99998731d8f306f373b6
ARG GH_ACTIONS_LOCK_ARM64_CHECKSUM=c79a279d6b0b635dc89ab6d38d0ecf98ff83abcee7bb483cd53353b74cd4f6df

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
