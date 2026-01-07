FROM ghcr.io/dependabot/dependabot-updater-core

# Install OCaml and opam
USER root

# Install system dependencies
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        opam \
        ocaml \
        build-essential \
        m4 \
        unzip \
        bubblewrap \
    && rm -rf /var/lib/apt/lists/*

# Initialize opam (as root to install system-wide)
RUN opam init --disable-sandboxing --bare -y

USER dependabot
