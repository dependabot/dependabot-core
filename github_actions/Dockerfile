# syntax=docker.io/docker/dockerfile:1.20
FROM ghcr.io/dependabot/dependabot-updater-core

ARG TARGETARCH
ARG GH_ACTIONS_LOCK_VERSION=v0.3.0
ARG GH_ACTIONS_LOCK_AMD64_CHECKSUM=15810767a8cd28d389f0942e3ce515ac0008c3f65301c3834fd4c046d4bda497
ARG GH_ACTIONS_LOCK_ARM64_CHECKSUM=ad978d58be9d3570c6f556c5c86e84248e922f3adf022e153073bbfea8d1bbef

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
