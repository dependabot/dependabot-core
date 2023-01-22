FROM ghcr.io/dependabot/dependabot-updater-core
ARG TARGETARCH=amd64
ARG TERRAFORM_VERSION=1.3.7
ARG TERRAFORM_AMD64_CHECKSUM=b8cf184dee15dfa89713fe56085313ab23db22e17284a9a27c0999c67ce3021e
ARG TERRAFORM_ARM64_CHECKSUM=5b491c555ea8a62dda551675fd9f27d369f5cdbe87608d2a7367d3da2d38ea38
RUN cd /tmp \
  && curl -o terraform-${TARGETARCH}.tar.gz https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${TARGETARCH}.zip \
  && printf "$TERRAFORM_AMD64_CHECKSUM terraform-amd64.tar.gz\n$TERRAFORM_ARM64_CHECKSUM terraform-arm64.tar.gz\n" | sha256sum -c --ignore-missing - \
  && unzip -d /usr/local/bin terraform-${TARGETARCH}.tar.gz \
  && rm terraform-${TARGETARCH}.tar.gz

USER dependabot
COPY --chown=dependabot:dependabot terraform/helpers /opt/terraform/helpers
RUN bash /opt/terraform/helpers/build

COPY --chown=dependabot:dependabot terraform /home/dependabot/terraform
