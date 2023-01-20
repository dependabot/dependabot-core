FROM ghcr.io/dependabot/dependabot-updater-core
ARG BUNDLER_V1_VERSION=1.17.3
RUN apt-get update \
  && apt-get upgrade -y \
  && apt-get install -y --no-install-recommends \
    curl \
  && gem install bundler -v $BUNDLER_V2_VERSION --no-document
USER dependabot

COPY --chown=dependabot:dependabot bundler/helpers /opt/bundler/helpers
RUN bash /opt/bundler/helpers/v1/build \
  && bash /opt/bundler/helpers/v2/build

COPY --chown=dependabot:dependabot bundler /home/dependabot/bundler
