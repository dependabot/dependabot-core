# TODO: download osv-scanner from https://github.com/google/osv-scanner/releases
# once maven remediation features are formally released.
FROM docker.io/library/golang:1.22.7-bookworm AS go
ARG OSV_SCANNER_VERSION=e054385a544da5981185fee64165c4d2ea4d889c
RUN go install "github.com/google/osv-scanner/cmd/osv-scanner@${OSV_SCANNER_VERSION}"

FROM ghcr.io/dependabot/dependabot-updater-core


ENV OSV_SCANNER_LOCAL_DB_CACHE_DIRECTORY="/opt/osv"
ENV DEPENDABOT_NATIVE_HELPERS_PATH="${OSV_SCANNER_LOCAL_DB_CACHE_DIRECTORY}/osv-scanner"
ENV PATH=${DEPENDABOT_NATIVE_HELPERS_PATH}:$PATH

USER dependabot
COPY --chown=dependabot:dependabot maven_osv $DEPENDABOT_HOME/maven_osv
COPY --chown=dependabot:dependabot common $DEPENDABOT_HOME/common
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
COPY --chown=dependabot:dependabot --from=go /go/bin/osv-scanner $DEPENDABOT_NATIVE_HELPERS_PATH/osv-scanner

RUN mkdir -p "${OSV_SCANNER_LOCAL_DB_CACHE_DIRECTORY}/osv-scanner/Maven" && \
    curl --output "${OSV_SCANNER_LOCAL_DB_CACHE_DIRECTORY}/osv-scanner/Maven/all.zip" \
                  https://osv-vulnerabilities.storage.googleapis.com/Maven/all.zip