FROM ghcr.io/dependabot/dependabot-updater-core
ARG TARGETARCH

# See https://github.com/hashicorp/terraform/releases or https://releases.hashicorp.com/terraform/
ARG TERRAFORM_VERSION=1.6.1

# curl "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_SHA256SUMS" | grep "terraform_${TERRAFORM_VERSION}_linux_amd64.zip"
ARG TERRAFORM_AMD64_CHECKSUM=d1a778850cc44d9348312c9527f471ea1b7a9213205bb5091ec698f3dc92e2a6

# curl "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_SHA256SUMS" | grep "terraform_${TERRAFORM_VERSION}_linux_arm64.zip"
ARG TERRAFORM_ARM64_CHECKSUM=ae328d5733657f35233fd228d9a14fccde3b1d19b99158eff1906888b3ca4935

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
