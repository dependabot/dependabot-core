FROM golang:alpine AS builder

RUN apk add --no-cache \
        git \
        gcc

COPY helpers /opt/go_modules/helpers
RUN ash /opt/go_modules/helpers/build /opt/go_modules

FROM dependabot/dependabot-common

RUN apk add --no-cache \
        go

COPY --from=builder /opt/go_modules/bin /opt/go_modules/bin
