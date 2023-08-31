FROM ghcr.io/dependabot/dependabot-updater-core

USER root

# Install Rust
ENV RUSTUP_HOME=/opt/rust \
  CARGO_HOME=/opt/rust \
  CARGO_REGISTRIES_CRATES_IO_PROTOCOL=sparse \
  PATH="${PATH}:/opt/rust/bin"
RUN mkdir -p "$RUSTUP_HOME" && chown dependabot:dependabot "$RUSTUP_HOME"

USER dependabot
# Look for updates at https://github.com/rust-lang/rust/releases
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y --default-toolchain 1.69.0 --profile minimal

# Configure cargo to use Git CLI so the Git shim works
RUN mkdir -p ~/.cargo && printf "[net]\ngit-fetch-with-cli = true\n" >> ~/.cargo/config.toml

COPY --chown=dependabot:dependabot cargo $DEPENDABOT_HOME/cargo
COPY --chown=dependabot:dependabot common $DEPENDABOT_HOME/common
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
