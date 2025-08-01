FROM ghcr.io/dependabot/dependabot-updater-core
ARG TARGETARCH

# Install minimal conda for conda search functionality
# Using miniconda3 to provide conda search command for version checking
# Determine the correct architecture for conda installer
# Docker TARGETARCH (arm64/amd64) -> Conda arch (aarch64/x86_64)
RUN CONDA_ARCH=$([ "$TARGETARCH" = "arm64" ] && echo "aarch64" || echo "x86_64") && \
  curl -fsSL https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-${CONDA_ARCH}.sh -o miniconda.sh && \
  bash miniconda.sh -b -p /opt/conda && \
  rm miniconda.sh && \
  /opt/conda/bin/conda config --set always_yes yes && \
  /opt/conda/bin/conda config --set changeps1 no && \
  /opt/conda/bin/conda clean -afy

# Add conda to PATH for conda search commands
ENV PATH="/opt/conda/bin:$PATH"

# Install YAML parsing tools for environment.yml processing
RUN pip install pyyaml

# Switch back to dependabot user for copying application files
USER dependabot

# Copy ecosystem-specific files
COPY --chown=dependabot:dependabot conda $DEPENDABOT_HOME/conda
COPY --chown=dependabot:dependabot common $DEPENDABOT_HOME/common
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
