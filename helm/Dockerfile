# From https://github.com/sigstore/cosign/releases
FROM ghcr.io/sigstore/cosign/cosign:v2.6.1 AS cosign
# From https://github.com/regclient/regclient/releases
FROM ghcr.io/regclient/regctl:v0.9.2 AS regctl
# From https://github.com/helm/helm/releases
FROM alpine/helm:3.17.2 AS helm

FROM ghcr.io/dependabot/dependabot-updater-core
ARG ORAS_VERSION=1.2.2

ENV PATH=/opt/bin:$PATH

COPY --from=regctl /regctl /opt/bin/regctl
COPY --from=cosign /ko-app/cosign /opt/bin/cosign
COPY --from=helm /usr/bin/helm /opt/bin/helm

RUN REGCTL_VERSION=$(regctl version --format '{{.VCSTag}}') && \
    cosign verify \
      --certificate-oidc-issuer https://token.actions.githubusercontent.com \
      --certificate-identity-regexp https://github.com/regclient/regclient/.github/workflows/ \
      ghcr.io/regclient/regctl:${REGCTL_VERSION} && \
    # Remove cosign as it is not needed in the final image
    rm /opt/bin/cosign

RUN cd /tmp \
  && curl -LO https://github.com/oras-project/oras/releases/download/v${ORAS_VERSION}/oras_${ORAS_VERSION}_linux_amd64.tar.gz \
  && mkdir -p oras-install/ \
  && tar -zxf oras_${ORAS_VERSION}_*.tar.gz -C oras-install/ \
  && mv oras-install/oras /opt/bin/oras \
  && rm -rf oras_${ORAS_VERSION}_*.tar.gz oras-install/

USER dependabot

COPY --chown=dependabot:dependabot helm $DEPENDABOT_HOME/helm
COPY --chown=dependabot:dependabot common $DEPENDABOT_HOME/common
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
COPY --chown=dependabot:dependabot docker $DEPENDABOT_HOME/docker
