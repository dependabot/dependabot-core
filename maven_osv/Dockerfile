# TODO: download osv-scanner from https://github.com/google/osv-scanner/releases
# once maven remediation features are formally released.
FROM docker.io/library/golang:1.22.7-bookworm as go
ARG OSV_SCANNER_VERSION=v1.9.1-0.20241015015803-cbe2f70b372b
RUN go install "github.com/google/osv-scanner/cmd/osv-scanner@${OSV_SCANNER_VERSION}"

FROM ghcr.io/dependabot/dependabot-updater-core


ENV DEPENDABOT_NATIVE_HELPERS_PATH="/opt"

USER dependabot
COPY --chown=dependabot:dependabot maven_osv $DEPENDABOT_HOME/maven_osv
COPY --chown=dependabot:dependabot common $DEPENDABOT_HOME/common
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
COPY --chown=dependabot:dependabot --from=go /go/bin/osv-scanner $DEPENDABOT_NATIVE_HELPERS_PATH/osv-scanner/osv-scanner

ENV PATH=${DEPENDABOT_NATIVE_HELPERS_PATH}/osv-scanner:$PATH

ENV OSV_SCANNER_OFFLINE_DB_DIR=${DEPENDABOT_NATIVE_HELPERS_PATH}/osv-scanner/Maven
RUN mkdir -p "${OSV_SCANNER_OFFLINE_DB_DIR}" && \
    curl --output "${OSV_SCANNER_OFFLINE_DB_DIR}/all.zip" https://osv-vulnerabilities.storage.googleapis.com/Maven/all.zip