# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/docker_compose/update_checker"
require "dependabot/docker/common/shared_examples_for_docker_update_checkers.rb"

RSpec.describe Dependabot::DockerCompose::UpdateChecker do
  let(:file_name) { "docker-compose.yml" }
  let(:package_manager) { "docker_compose" }

  it_behaves_like "a Docker update checker"
end
