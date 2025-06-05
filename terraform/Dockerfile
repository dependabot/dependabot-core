FROM ghcr.io/dependabot/dependabot-updater-core
ARG TARGETARCH

# See https://github.com/hashicorp/terraform/releases or https://releases.hashicorp.com/terraform/
ARG TERRAFORM_VERSION=1.12.1

# curl "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_SHA256SUMS" | grep "terraform_${TERRAFORM_VERSION}_linux_amd64.zip"
ARG TERRAFORM_AMD64_CHECKSUM=dcaf8ba801660a431a6769ec44ba53b66c1ad44637512ef3961f7ffe4397ef7c

# curl "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_SHA256SUMS" | grep "terraform_${TERRAFORM_VERSION}_linux_arm64.zip"
ARG TERRAFORM_ARM64_CHECKSUM=70e8c1776646f2af83ccad6113b8bb4768e6f7dc65335ae11ffd095eca3b0d4c

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
