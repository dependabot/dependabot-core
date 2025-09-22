# From https://github.com/sigstore/cosign/releases
FROM ghcr.io/sigstore/cosign/cosign:v2.5.2 AS cosign
# From https://github.com/regclient/regclient/releases
FROM ghcr.io/regclient/regctl:v0.9.2 AS regctl

FROM ghcr.io/dependabot/dependabot-updater-core

ENV PATH=/opt/bin:$PATH
COPY --from=regctl /regctl /opt/bin/regctl
COPY --from=cosign /ko-app/cosign /opt/bin/cosign

RUN chmod o+rx /opt/bin/regctl &&  \
    chmod +x /opt/bin/cosign

# Verify regclient binary. See https://regclient.org/install/#verifying-signatures
RUN REGCTL_VERSION=$(regctl version --format '{{.VCSTag}}') && \
    cosign verify \
      --certificate-oidc-issuer https://token.actions.githubusercontent.com \
      --certificate-identity-regexp https://github.com/regclient/regclient/.github/workflows/ \
      ghcr.io/regclient/regctl:${REGCTL_VERSION} && \
    # Remove cosign as it is not needed in the final image
    rm /opt/bin/cosign

USER dependabot

COPY --chown=dependabot:dependabot docker $DEPENDABOT_HOME/docker
COPY --chown=dependabot:dependabot common $DEPENDABOT_HOME/common
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
