# syntax=docker.io/docker/dockerfile:1.20
FROM docker.io/library/rust:1.89.0-bookworm AS rust

FROM ghcr.io/dependabot/dependabot-updater-core

USER root

# Install Rust
ENV RUSTUP_HOME=/opt/rust \
  CARGO_HOME=/opt/rust \
  CARGO_REGISTRIES_CRATES_IO_PROTOCOL=sparse \
  PATH="${PATH}:/opt/rust/bin"
RUN mkdir -p "$RUSTUP_HOME" && chown dependabot:dependabot "$RUSTUP_HOME"

USER dependabot

COPY --from=rust /usr/local/rustup $RUSTUP_HOME
COPY --from=rust /usr/local/cargo $CARGO_HOME

# Configure cargo to use Git CLI so the Git shim works
RUN mkdir -p ~/.cargo && printf "[net]\ngit-fetch-with-cli = true\n" >> ~/.cargo/config.toml

COPY --chown=dependabot:dependabot --parents cargo common $DEPENDABOT_HOME/
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
