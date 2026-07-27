# syntax=docker.io/docker/dockerfile:1.20
FROM ghcr.io/dependabot/dependabot-updater-core

ARG TARGETARCH
ARG GH_ACTIONS_LOCK_VERSION=v0.1.6-rc.2
ARG GH_ACTIONS_LOCK_AMD64_CHECKSUM=be371ae7e91b387193a2a6a89cfc2f4c28054fe0fcdfa0b19badc647dae29453
ARG GH_ACTIONS_LOCK_ARM64_CHECKSUM=2a742ccd9430645a6b4834e15867165819583c25cb6d9f6c77c42f9c92b7e135

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
