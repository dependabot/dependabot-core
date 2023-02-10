FROM ghcr.io/dependabot/dependabot-updater-core
ARG TARGETARCH
ARG TERRAFORM_VERSION=1.3.8
ARG TERRAFORM_AMD64_CHECKSUM=9d9e7d6a9b41cef8b837af688441d4fbbd84b503d24061d078ad662441c70240
ARG TERRAFORM_ARM64_CHECKSUM=a42bf3c7d6327f45d2b212b692ab4229285fb44dbb8adb7c39e18be2b26167c8
RUN cd /tmp \
  && curl -o terraform-${TARGETARCH}.tar.gz https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${TARGETARCH}.zip \
  && printf "$TERRAFORM_AMD64_CHECKSUM terraform-amd64.tar.gz\n$TERRAFORM_ARM64_CHECKSUM terraform-arm64.tar.gz\n" | sha256sum -c --ignore-missing - \
  && unzip -d /usr/local/bin terraform-${TARGETARCH}.tar.gz \
  && rm terraform-${TARGETARCH}.tar.gz

USER dependabot
COPY --chown=dependabot:dependabot terraform/helpers /opt/terraform/helpers
RUN bash /opt/terraform/helpers/build

COPY --chown=dependabot:dependabot terraform /home/dependabot/terraform
