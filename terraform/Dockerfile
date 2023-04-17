FROM ghcr.io/dependabot/dependabot-updater-core
ARG TARGETARCH
ARG TERRAFORM_VERSION=1.4.5
ARG TERRAFORM_AMD64_CHECKSUM=ce10e941cd11554b15a189cd00191c05abc20dff865599d361bdb863c5f406a9
ARG TERRAFORM_ARM64_CHECKSUM=ca2c48f518f72fef668255150cc5e63b92545edc62a05939bbff8a350bceb357
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
