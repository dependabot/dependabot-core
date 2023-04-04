FROM ghcr.io/dependabot/dependabot-updater-core
ARG TARGETARCH

USER root

# Install Go
ARG GOLANG_VERSION=1.20.2

# You can find the SHA's here: https://go.dev/dl/
ARG GOLANG_AMD64_CHECKSUM=4eaea32f59cde4dc635fbc42161031d13e1c780b87097f4b4234cfce671f1768
ARG GOLANG_ARM64_CHECKSUM=78d632915bb75e9a6356a47a42625fd1a785c83a64a643fedd8f61e31b1b3bef

ENV PATH=/opt/go/bin:$PATH
RUN cd /tmp \
  && curl --location --http1.1 -o go-${TARGETARCH}.tar.gz https://go.dev/dl/go${GOLANG_VERSION}.linux-${TARGETARCH}.tar.gz \
  && printf "$GOLANG_AMD64_CHECKSUM go-amd64.tar.gz\n$GOLANG_ARM64_CHECKSUM go-arm64.tar.gz\n" | sha256sum -c --ignore-missing - \
  && tar -xzf go-${TARGETARCH}.tar.gz -C /opt \
  && rm go-${TARGETARCH}.tar.gz

ENV DEPENDABOT_NATIVE_HELPERS_PATH="/opt"

COPY go_modules/helpers /opt/go_modules/helpers
RUN bash /opt/go_modules/helpers/build

USER dependabot
COPY --chown=dependabot:dependabot go_modules /home/dependabot/go_modules
