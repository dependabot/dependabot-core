FROM docker.ci.pix4d.com/dependabot-ruby-base:latest AS main
LABEL "maintainer"="integration_team@pix4d.com"
LABEL "description"="Inspect Concourse pipelines and find possible updates to Docker images \
    checking a specified registry."

COPY concourse /home/dependabot/concourse
COPY Gemfile /home/dependabot/
COPY update_script.rb /home/dependabot/

RUN bundle install

FROM main AS tests

WORKDIR /home/dependabot/concourse/
RUN bundle exec rspec ./spec/

FROM main
