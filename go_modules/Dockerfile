FROM docker.io/library/golang:1.22.5-bookworm as go

FROM ghcr.io/dependabot/dependabot-updater-core
ARG TARGETARCH

USER root

COPY --from=go /usr/local/go /opt/go

ENV PATH=/opt/go/bin:$PATH

ENV DEPENDABOT_NATIVE_HELPERS_PATH="/opt"

COPY go_modules/helpers /opt/go_modules/helpers
RUN bash /opt/go_modules/helpers/build

USER dependabot
COPY --chown=dependabot:dependabot go_modules $DEPENDABOT_HOME/go_modules
COPY --chown=dependabot:dependabot common $DEPENDABOT_HOME/common
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater

# See https://go.dev/doc/toolchain#select
# By specifying go1.20.10, we use 1.20.10 for any go.mod with go directive <= 1.20.
# In the file_parser, GOTOOLCHAIN=local+auto is set otherwise, which uses the latest version above
# or downloads the correct version if it's later than the version installed.
ENV GOTOOLCHAIN="go1.20.10"
# This pre-installs go 1.20 so that each job doesn't have to do it.
RUN go version
ENV GO_LEGACY=$GOTOOLCHAIN

# Enable automatic pulling of files stored with Git LFS.
# This is crucial for the Go toolchain to correctly compute module hashes in repositories
# with LFS committed files.
# This is relevant only for Go Modules embedding (with //go:embed) large files and does not
# affect repositories that do not commit files to LFS.
ENV GIT_LFS_SKIP_SMUDGE=1
