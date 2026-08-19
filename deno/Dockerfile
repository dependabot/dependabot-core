# syntax=docker.io/docker/dockerfile:1.20
FROM ghcr.io/dependabot/dependabot-updater-core

ARG DENO_VERSION=2.8.3

USER root

RUN curl -fsSL https://deno.land/install.sh | DENO_INSTALL=/usr/local sh -s v${DENO_VERSION}

# All registry traffic is intercepted by Dependabot's MITM proxy, which presents a
# certificate signed by its own CA (injected into the system bundle at runtime).
# Deno 2.8+ honors NODE_EXTRA_CA_CERTS at the root certificate store level — so it's
# applied to fetch(), jsr/npm downloads, and node compat — letting `deno install`
# trust the proxy. Missing/invalid files only warn, so local runs are unaffected.
# Mirrors npm_and_yarn / bun.
ENV NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt

USER dependabot

COPY --chown=dependabot:dependabot --parents deno common $DEPENDABOT_HOME/
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
