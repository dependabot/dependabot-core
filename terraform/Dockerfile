FROM ghcr.io/dependabot/dependabot-updater-core
ARG TARGETARCH
ARG TERRAFORM_VERSION=1.4.4
ARG TERRAFORM_AMD64_CHECKSUM=67541c1f6631befcc25b764028e5605e59234d4424e60a256518ee1e8dd50593
ARG TERRAFORM_ARM64_CHECKSUM=5fc610f1554be7132a59542696094ad80a87ccdd3cac50a77f8ae4f7570bb0a4
RUN cd /tmp \
  && curl -o terraform-${TARGETARCH}.tar.gz https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${TARGETARCH}.zip \
  && printf "$TERRAFORM_AMD64_CHECKSUM terraform-amd64.tar.gz\n$TERRAFORM_ARM64_CHECKSUM terraform-arm64.tar.gz\n" | sha256sum -c --ignore-missing - \
  && unzip -d /usr/local/bin terraform-${TARGETARCH}.tar.gz \
  && rm terraform-${TARGETARCH}.tar.gz

USER dependabot
COPY --chown=dependabot:dependabot terraform/helpers /opt/terraform/helpers
RUN bash /opt/terraform/helpers/build

COPY --chown=dependabot:dependabot terraform /home/dependabot/terraform
