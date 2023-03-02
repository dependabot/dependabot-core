FROM ghcr.io/dependabot/dependabot-updater-core
ARG TARGETARCH
ARG TERRAFORM_VERSION=1.3.9
ARG TERRAFORM_AMD64_CHECKSUM=53048fa573effdd8f2a59b726234c6f450491fe0ded6931e9f4c6e3df6eece56
ARG TERRAFORM_ARM64_CHECKSUM=da571087268c5faf884912c4239c6b9c8e1ed8e8401ab1dcb45712df70f42f1b
RUN cd /tmp \
  && curl -o terraform-${TARGETARCH}.tar.gz https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${TARGETARCH}.zip \
  && printf "$TERRAFORM_AMD64_CHECKSUM terraform-amd64.tar.gz\n$TERRAFORM_ARM64_CHECKSUM terraform-arm64.tar.gz\n" | sha256sum -c --ignore-missing - \
  && unzip -d /usr/local/bin terraform-${TARGETARCH}.tar.gz \
  && rm terraform-${TARGETARCH}.tar.gz

USER dependabot
COPY --chown=dependabot:dependabot terraform/helpers /opt/terraform/helpers
RUN bash /opt/terraform/helpers/build

COPY --chown=dependabot:dependabot terraform /home/dependabot/terraform
