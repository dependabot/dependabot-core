# syntax=docker.io/docker/dockerfile:1.20
FROM docker.io/library/golang:1.27.0-bookworm AS gh-actions-lock
RUN CGO_ENABLED=0 GOBIN=/out go install \
      github.com/github/gh-actions-lock/cmd/gh-actions-lock@c5ee15d8f20e3e52d6671851192770b9a2e02152

FROM ghcr.io/dependabot/dependabot-updater-core

# TEMP(staging): gh-actions-lock built from github/gh-actions-lock#137; swap back to a release pin before review.
COPY --from=gh-actions-lock /out/gh-actions-lock /opt/github_actions/bin/gh-actions-lock

USER dependabot

COPY --chown=dependabot:dependabot --parents github_actions common $DEPENDABOT_HOME/
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
