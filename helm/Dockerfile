# syntax=docker.io/docker/dockerfile:1.20
# Dependabot should generally handle keeping these files up to date, though there may be situations where a manual update is required.
# When updating digests, always use the Multiplatform digest rather than one specific to a single architecture.
# Tools like `docker buildx imagetools` can help you locate the Multiplatform digest
# If you perform a manual update, make sure to update the tag as well.
# Including the tag with the digest is for documentation purposes, as Docker ignores the tag when a digest is provided
# It helps because mapping tags to digests is difficult without OCI metadata and not all the images publish this metadata
# From https://github.com/sigstore/cosign/releases
FROM ghcr.io/sigstore/cosign/cosign:v3.1.3@sha256:9e5c2f2edc34351160407ca3416c61855bdf9403c3c5936e0f0be7fc261611b8 AS cosign
# From https://github.com/regclient/regclient/releases
FROM ghcr.io/regclient/regctl:v0.11.5@sha256:dbe356c6cf9f8f85e302b9e47fed481ef3f1b04807350e99b02ab2cadee0a993 AS regctl
# From https://github.com/helm/helm/releases
FROM alpine/helm:4.2.4@sha256:76c375eed56144c68d6197c55bc5a4552fb42002190b796729901cbab3ae6e51 AS helm
# From https://github.com/oras-project/oras/releases
FROM ghcr.io/oras-project/oras:v1.3.4@sha256:f7bc056d54d97baa399414ed5048ecc67c3371b750d4bbce1d871827a5758179 AS oras

# The builder needs to be an image with the cacerts because cosign verification needs them
# We could use a smaller base image and install the cacerts, but
# at that point, we can just use the dependabot-updater-core as the base image
# and save us another pull as it is already used as the final image
FROM ghcr.io/dependabot/dependabot-updater-core AS builder

COPY  --chown=dependabot:dependabot --from=regctl /regctl $DEPENDABOT_HOME/tools/regctl
COPY  --chown=dependabot:dependabot --from=cosign /ko-app/cosign $DEPENDABOT_HOME/tools/cosign
COPY  --chown=dependabot:dependabot --from=helm /usr/bin/helm $DEPENDABOT_HOME/tools/helm
COPY  --chown=dependabot:dependabot --from=oras /bin/oras $DEPENDABOT_HOME/tools/oras

ENV PATH=/opt/bin/dependabot-tools:$PATH

# Verify regctl signature
RUN <<EOF
      REGCTL_VERSION=$(regctl version --format '{{.VCSTag}}')
      cosign verify \
            --certificate-oidc-issuer https://token.actions.githubusercontent.com \
            --certificate-identity-regexp https://github.com/regclient/regclient/.github/workflows/ \
            ghcr.io/regclient/regctl:${REGCTL_VERSION}
      # Remove cosign as it is not needed in the final image
       rm $DEPENDABOT_HOME/tools/cosign
EOF

COPY --chown=dependabot:dependabot --parents docker helm common $DEPENDABOT_HOME
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater

FROM ghcr.io/dependabot/dependabot-updater-core

USER dependabot

COPY --from=builder $DEPENDABOT_HOME $DEPENDABOT_HOME
ENV PATH=$DEPENDABOT_HOME/tools:$PATH
