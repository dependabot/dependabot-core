# Use the official Go 1.23.0 image as the base for building Go tools
FROM docker.io/library/golang:1.23.0-bookworm AS go

# Use the Dependabot Updater Core image
FROM ghcr.io/dependabot/dependabot-updater-core
ARG TARGETARCH

USER root

# Copy Go binaries from the Go base image to the final image
COPY --from=go /usr/local/go /opt/go

# Update the PATH to include Go binaries
ENV PATH=/opt/go/bin:$PATH

# Set the native helpers path for Dependabot
ENV DEPENDABOT_NATIVE_HELPERS_PATH="/opt"

# Copy the helper files for building the Go modules
COPY go_modules/helpers /opt/go_modules/helpers
RUN bash /opt/go_modules/helpers/build

USER dependabot
# Copy the modules, common, and updater files
COPY --chown=dependabot:dependabot go_modules $DEPENDABOT_HOME/go_modules
COPY --chown=dependabot:dependabot common $DEPENDABOT_HOME/common
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater

# Set the Go toolchain to the correct version (go1.23.x, fix the toolchain version format)
ENV GOTOOLCHAIN="go1.23.0"
# This pre-installs Go 1.23 so that each job doesn't have to download it.
RUN go version
ENV GO_LEGACY=$GOTOOLCHAIN
