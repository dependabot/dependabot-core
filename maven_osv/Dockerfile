FROM ghcr.io/dependabot/dependabot-updater-core

USER dependabot
COPY --chown=dependabot:dependabot maven_osv $DEPENDABOT_HOME/maven_osv
COPY --chown=dependabot:dependabot common $DEPENDABOT_HOME/common
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater

ENV OSV_SCANNER_OFFLINE_DB_DIR=${DEPENDABOT_HOME}/osv-scanner/Maven
RUN mkdir -p "${OSV_SCANNER_OFFLINE_DB_DIR}" && \
    curl --output "${OSV_SCANNER_OFFLINE_DB_DIR}/all.zip" https://osv-vulnerabilities.storage.googleapis.com/Maven/all.zip