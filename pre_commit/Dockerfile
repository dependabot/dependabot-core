# syntax=docker.io/docker/dockerfile:1.20
ARG UPDATER_CORE_IMAGE=ghcr.io/dependabot/dependabot-updater-core

FROM docker.io/library/golang:1.25.0-bookworm AS go

FROM ${UPDATER_CORE_IMAGE}
ARG TARGETARCH

USER root

COPY --from=go /usr/local/go /opt/go
ENV PATH=/opt/go/bin:$PATH

# Install minimal conda for conda additional_dependencies support
# Using miniconda3 to provide conda search command for version checking
RUN CONDA_ARCH=$([ "$TARGETARCH" = "arm64" ] && echo "aarch64" || echo "x86_64") && \
  curl -fsSL https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-${CONDA_ARCH}.sh -o miniconda.sh && \
  bash miniconda.sh -b -p /opt/conda && \
  rm miniconda.sh && \
  /opt/conda/bin/conda config --set always_yes yes && \
  /opt/conda/bin/conda config --set changeps1 no && \
  /opt/conda/bin/conda clean -afy

# Add conda to PATH for conda search commands
ENV PATH="/opt/conda/bin:$PATH"

ENV DEPENDABOT_NATIVE_HELPERS_PATH="/opt"

COPY go_modules/helpers /opt/go_modules/helpers
RUN bash /opt/go_modules/helpers/build

USER dependabot

# Install bundler native helpers for Ruby additional_dependencies support
COPY --chown=dependabot:dependabot bundler/helpers /opt/bundler/helpers
RUN bash /opt/bundler/helpers/v2/build

COPY --chown=dependabot:dependabot --parents go_modules cargo npm_and_yarn python pre_commit common bundler conda $DEPENDABOT_HOME/
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
