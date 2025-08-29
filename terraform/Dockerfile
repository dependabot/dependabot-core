# Terraform does not currently offer a documented way to verify image signatures.
# Reference: https://github.com/hashicorp/terraform/issues/37518
# For now, we can confirm that the image digest matches the official HashiCorp published value
# We can, however, still benefit from automated Dependabot updates to keep this image up to date.
FROM hashicorp/terraform:1.12.2@sha256:f5ac787eee9d292b6a3b97d40f04019ce08189d356233fc73d5ec7ef8529cce2 AS terraform

FROM ghcr.io/dependabot/dependabot-updater-core

COPY --from=terraform /bin/terraform /usr/local/bin/terraform

USER dependabot
COPY --chown=dependabot:dependabot terraform/helpers /opt/terraform/helpers
RUN bash /opt/terraform/helpers/build

COPY --chown=dependabot:dependabot terraform $DEPENDABOT_HOME/terraform
COPY --chown=dependabot:dependabot common $DEPENDABOT_HOME/common
COPY --chown=dependabot:dependabot updater $DEPENDABOT_HOME/dependabot-updater
