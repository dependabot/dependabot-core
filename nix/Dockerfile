# syntax=docker.io/docker/dockerfile:1.20
FROM docker.io/nixos/nix:2.34.7 AS nix

FROM ghcr.io/dependabot/dependabot-updater-core

# Copy Nix from the official image
COPY --from=nix --chown=dependabot:dependabot /nix /nix

# Configure Nix for single-user mode with flakes enabled.
# Additional language-level experimental features are enabled so user flakes
# that opt into them can still be evaluated when updating flake.lock:
#   - pipe-operators: |> and <| operators
#   - fetch-closure: builtins.fetchClosure
#   - parse-toml-timestamps: timestamp parsing in builtins.fromTOML
RUN mkdir -p /etc/nix \
  && echo "experimental-features = nix-command flakes pipe-operators fetch-closure parse-toml-timestamps" > /etc/nix/nix.conf \
  && echo "sandbox = false" >> /etc/nix/nix.conf

ENV PATH="/nix/var/nix/profiles/default/bin:${PATH}"

USER dependabot

COPY --chown=dependabot:dependabot --parents nix common $DEPENDABOT_HOME/
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
