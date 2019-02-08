FROM elixir:alpine AS builder

COPY helpers /opt/hex/helpers
RUN ash /opt/hex/helpers/build /opt/hex/dist

FROM dependabot/dependabot-common

RUN apk add --no-cache \
        elixir

COPY --from=builder /opt/hex/dist /opt/hex
