FROM ruby:2.7-alpine AS build

WORKDIR /home/dependabot/

ENV BUNDLE_PATH="/home/dependabot/.bundle" \
  BUNDLE_BIN=".bundle/binstubs" \
  PATH=".bundle/binstubs:$PATH:/home/dependabot/.bundle/bin"

COPY common /home/dependabot/common
COPY docker /home/dependabot/docker

RUN apk update && \
  apk add --no-cache \
  g++ \
  make && \
  gem update --system && \
  gem install bundler --no-document

WORKDIR /home/dependabot/docker/

RUN bundle install

FROM build AS tests

WORKDIR /home/dependabot/docker/
RUN bundle exec rspec ./spec/

FROM ruby:2.7-alpine AS main
LABEL "maintainer"="platform_ci_team@pix4d.com"
LABEL "description"="Inspect Dockerfiles and Concourse pipelines to find possible updates to Docker images \
  by checking a specified registry."

WORKDIR /home/dependabot/

ENV BUNDLE_PATH="/home/dependabot/.bundle" \
  BUNDLE_BIN=".bundle/binstubs" \
  PATH=".bundle/binstubs:$PATH:/home/dependabot/.bundle/bin"

COPY --from=build /home/dependabot/ .
