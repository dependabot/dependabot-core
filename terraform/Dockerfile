FROM ghcr.io/dependabot/dependabot-updater-core
ARG TARGETARCH

# See https://github.com/hashicorp/terraform/releases or https://releases.hashicorp.com/terraform/
ARG TERRAFORM_VERSION=1.12.0

# curl "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_SHA256SUMS" | grep "terraform_${TERRAFORM_VERSION}_linux_amd64.zip"
ARG TERRAFORM_AMD64_CHECKSUM=c71fd5d500a7e4d869bf5d12176c72d1dfc00440b862116797694361671f77c8

# curl "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_SHA256SUMS" | grep "terraform_${TERRAFORM_VERSION}_linux_arm64.zip"
ARG TERRAFORM_ARM64_CHECKSUM=8174792e28419601db6445f3252f792bc84c14358f6fe1c65d2951d89b36fadf

RUN cd /tmp \
  && curl -o terraform-${TARGETARCH}.tar.gz https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${TARGETARCH}.zip \
  && printf "$TERRAFORM_AMD64_CHECKSUM terraform-amd64.tar.gz\n$TERRAFORM_ARM64_CHECKSUM terraform-arm64.tar.gz\n" | sha256sum -c --ignore-missing - \
  && unzip -d /usr/local/bin terraform-${TARGETARCH}.tar.gz \
  && rm terraform-${TARGETARCH}.tar.gz

USER dependabot
COPY --chown=dependabot:dependabot terraform/helpers /opt/terraform/helpers
RUN bash /opt/terraform/helpers/build

COPY --chown=dependabot:dependabot terraform $DEPENDABOT_HOME/terraform
COPY --chown=dependabot:dependabot common $DEPENDABOT_HOME/common
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
