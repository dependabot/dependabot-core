# syntax=docker.io/docker/dockerfile:1.20
# Dependabot should generally handle keeping these files up to date, though there may be situations where a manual update is required.
# When updating digests, always use the Multiplatform digest rather than one specific to a single architecture.
# Tools like `docker buildx imagetools` can help you locate the Multiplatform digest
# If you perform a manual update, make sure to update the tag as well.
# Including the tag with the digest is for documentation purposes, as Docker ignores the tag when a digest is provided
# It helps because mapping tags to digests is difficult without OCI metadata and not all the images publish this metadata
# From https://github.com/sigstore/cosign/releases
FROM ghcr.io/sigstore/cosign/cosign:v3.0.2@sha256:b29487e48205d875c324c79583e2806d9d269c0fa299e0861bbec023d8430c8b AS cosign
# From https://github.com/regclient/regclient/releases
FROM ghcr.io/regclient/regctl:v0.10.0@sha256:c10b839d91d66b2ce9f4fa588f1b576c51c4709934aeb782ef175a20fd49942d AS regctl
# From https://github.com/helm/helm/releases
FROM alpine/helm:3.17.2@sha256:b80eb190fca14707e94a5090235a3f1bf2f206f26761f2890d16a1e570386236 AS helm
# From https://github.com/oras-project/oras/releases
FROM ghcr.io/oras-project/oras:v1.2.2@sha256:cd549d80c4aa89638aea5964a3cd8193a6dd8abf939a43b5d562c24dbab08ff1 AS oras

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
