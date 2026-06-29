# syntax=docker.io/docker/dockerfile:1.20
FROM ghcr.io/dependabot/dependabot-updater-core

ARG DEVBOX_VERSION=0.17.5
ARG TARGETARCH=amd64

USER root

# Install the pinned devbox CLI, mirroring deno's ARG-pinned binary install.
RUN curl -fsSL "https://github.com/jetify-com/devbox/releases/download/${DEVBOX_VERSION}/devbox_${DEVBOX_VERSION}_linux_${TARGETARCH}.tar.gz" \
    -o /tmp/devbox.tar.gz \
  && tar -xzf /tmp/devbox.tar.gz -C /usr/local/bin devbox \
  && chmod +x /usr/local/bin/devbox \
  && rm /tmp/devbox.tar.gz

# Devbox resolves nixpkgs packages through Nix, so it must be available for
# `devbox update` to regenerate devbox.lock. Install Nix without a daemon
# (the updater container has no init system). `sandbox = false` because the
# container is already isolated and lacks the privileges Nix's sandbox needs;
# `filter-syscalls = false` because Docker's seccomp profile blocks Nix from
# loading its own syscall filter ("unable to load seccomp BPF program").
RUN curl --proto '=https' --tlsv1.2 -sSfL https://install.determinate.systems/nix \
    | sh -s -- install linux --init none --no-confirm \
      --extra-conf "sandbox = false" \
      --extra-conf "filter-syscalls = false"
ENV PATH="/nix/var/nix/profiles/default/bin:${PATH}"

# Registry/cache traffic is intercepted by Dependabot's MITM proxy, which presents
# a certificate signed by its own CA (injected into the system bundle at runtime).
# Point Nix at that bundle so package resolution trusts the proxy.
ENV NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

USER dependabot

COPY --chown=dependabot:dependabot --parents devbox common $DEPENDABOT_HOME/
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
