# syntax=docker.io/docker/dockerfile:1.20

# Builds the native helper (an uberjar). The Clojure CLI is only needed here.
FROM docker.io/library/clojure:temurin-21-tools-deps-1.12.5.1664-bookworm-slim@sha256:ea7bf90f7977e23bcd0c1640d4e3c9bcaeeeb0f6ca0c5990b115108323f34263 AS helper-build

ENV DEPENDABOT_NATIVE_HELPERS_PATH="/opt"
COPY clojure/helpers /opt/clojure/helpers
RUN bash /opt/clojure/helpers/build

FROM ghcr.io/dependabot/dependabot-updater-core

# The helper only parses files and makes no network calls, so a JRE is enough.
RUN apt-get update && apt-get install -y --no-install-recommends \
    openjdk-21-jre-headless \
    && rm -rf /var/lib/apt/lists/*

ENV DEPENDABOT_NATIVE_HELPERS_PATH="/opt"
COPY --from=helper-build --chown=dependabot:dependabot /opt/clojure/clojure-helper.jar /opt/clojure/clojure-helper.jar

USER dependabot

COPY --chown=dependabot:dependabot --parents clojure maven common $DEPENDABOT_HOME/
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
