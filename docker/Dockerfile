FROM ghcr.io/dependabot/dependabot-updater-core
ARG TARGETARCH

# Install regctl
ARG REGCTL_VERSION=0.4.7
# These are manually calculated as they are not provided by the maintainer
ARG REGCTL_AMD64_CHECKSUM=8cabc58130279c3c93636d48633ec2763bf3f9c389dc1f693aabfe30a204d834
ARG REGCTL_ARM64_CHECKSUM=5dc1c8430441e92dcbff75dc98a880b04027b284e541aeda5e7fc35a33255ba7

ENV PATH=/opt/bin:$PATH
RUN cd /tmp \
  && curl -sSf -o regctl-${TARGETARCH} -L https://github.com/regclient/regclient/releases/download/v${REGCTL_VERSION}/regctl-linux-${TARGETARCH} \
  && printf "$REGCTL_AMD64_CHECKSUM regctl-amd64\n$REGCTL_ARM64_CHECKSUM regctl-arm64\n" | sha256sum -c --ignore-missing - \
  && mkdir /opt/bin \
  && mv regctl-${TARGETARCH} /opt/bin/regctl \
  && chmod o+rx /opt/bin/regctl

USER dependabot

COPY --chown=dependabot:dependabot docker /home/dependabot/docker
