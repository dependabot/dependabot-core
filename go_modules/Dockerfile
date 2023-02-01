FROM ghcr.io/dependabot/dependabot-updater-core
ARG TARGETARCH

USER root

# Install Go
ARG GOLANG_VERSION=1.19
# You can find the sha here: https://storage.googleapis.com/golang/go${GOLANG_VERSION}.linux-amd64.tar.gz.sha256
ARG GOLANG_AMD64_CHECKSUM=464b6b66591f6cf055bc5df90a9750bf5fbc9d038722bb84a9d56a2bea974be6
ARG GOLANG_ARM64_CHECKSUM=efa97fac9574fc6ef6c9ff3e3758fb85f1439b046573bf434cccb5e012bd00c8

ENV PATH=/opt/go/bin:$PATH
RUN cd /tmp \
  && curl --http1.1 -o go-${TARGETARCH}.tar.gz https://dl.google.com/go/go${GOLANG_VERSION}.linux-${TARGETARCH}.tar.gz \
  && printf "$GOLANG_AMD64_CHECKSUM go-amd64.tar.gz\n$GOLANG_ARM64_CHECKSUM go-arm64.tar.gz\n" | sha256sum -c --ignore-missing - \
  && tar -xzf go-${TARGETARCH}.tar.gz -C /opt \
  && rm go-${TARGETARCH}.tar.gz

ENV DEPENDABOT_NATIVE_HELPERS_PATH="/opt"

COPY go_modules/helpers /opt/go_modules/helpers
RUN bash /opt/go_modules/helpers/build

USER dependabot
COPY --chown=dependabot:dependabot go_modules /home/dependabot/go_modules
