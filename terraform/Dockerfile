FROM alpine AS builder

COPY helpers /opt/terraform/helpers
RUN ash /opt/terraform/helpers/build /opt/terraform

FROM dependabot/dependabot-common

COPY --from=builder /opt/terraform/bin /opt/terraform/bin
