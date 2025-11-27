FROM docker.io/crystallang/crystal:1.15.1-alpine AS crystal

FROM ghcr.io/dependabot/dependabot-updater-core
ARG TARGETARCH

USER root

# Copy Crystal from official image
COPY --from=crystal /usr/bin/crystal /opt/crystal/bin/crystal
COPY --from=crystal /usr/bin/shards /opt/crystal/bin/shards
COPY --from=crystal /usr/lib/crystal /opt/crystal/lib/crystal

ENV PATH="/opt/crystal/bin:$PATH"

# Install Crystal runtime dependencies
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    gcc \
    pkg-config \
    libpcre3-dev \
    libevent-dev \
    libssl-dev \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

USER dependabot

COPY --chown=dependabot:dependabot crystal_shards $DEPENDABOT_HOME/crystal_shards
COPY --chown=dependabot:dependabot common $DEPENDABOT_HOME/common
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
