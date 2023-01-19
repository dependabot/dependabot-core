FROM ghcr.io/dependabot/dependabot-updater-core

USER root
RUN apt-get update \
  && apt-get upgrade -y \
  && apt-get install -y --no-install-recommends curl

# Install Rust
ENV RUSTUP_HOME=/opt/rust \
  CARGO_HOME=/opt/rust \
  PATH="${PATH}:/opt/rust/bin"
RUN mkdir -p "$RUSTUP_HOME" && chown dependabot:dependabot "$RUSTUP_HOME"

USER dependabot
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y --default-toolchain 1.66.0 --profile minimal

# Configure cargo to use Git CLI so the Git shim works
RUN mkdir -p ~/.cargo && printf "[net]\ngit-fetch-with-cli = true\n" >> ~/.cargo/config.toml

COPY --chown=dependabot:dependabot cargo /home/dependabot/cargo
