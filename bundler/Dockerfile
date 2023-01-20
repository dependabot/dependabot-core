FROM ghcr.io/dependabot/dependabot-updater-core

USER dependabot

COPY --chown=dependabot:dependabot bundler/helpers /opt/bundler/helpers
RUN bash /opt/bundler/helpers/v1/build \
  && bash /opt/bundler/helpers/v2/build

COPY --chown=dependabot:dependabot bundler /home/dependabot/bundler
