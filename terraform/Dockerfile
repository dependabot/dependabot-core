FROM ghcr.io/dependabot/dependabot-updater-core
ARG TARGETARCH

# See https://github.com/hashicorp/terraform/releases or https://releases.hashicorp.com/terraform/
ARG TERRAFORM_VERSION=1.5.3

# curl "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_SHA256SUMS" | grep "terraform_${TERRAFORM_VERSION}_linux_amd64.zip"
ARG TERRAFORM_AMD64_CHECKSUM=5ce4e0fc73d42b79f26ebb8c8d192bdbcff75bdc44e3d66895a48945b6ff5d48

# curl "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_SHA256SUMS" | grep "terraform_${TERRAFORM_VERSION}_linux_arm64.zip"
ARG TERRAFORM_ARM64_CHECKSUM=776c78281c1b517d1e2d9e78b2e60900b8ef9ecd51c4a5d2ffa68f66fea35dd2

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
