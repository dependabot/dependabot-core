FROM node:alpine AS builder

ENV DEPENDABOT_ENV="production"

COPY helpers /opt/npm_and_yarn/helpers
RUN /opt/npm_and_yarn/helpers/build /opt/npm_and_yarn/dist

FROM dependabot/dependabot-common

RUN apk add --no-cache \
        nodejs

COPY --from=builder /opt/npm_and_yarn/dist /opt/npm_and_yarn
