# typed: strict
# frozen_string_literal: true

require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/docker_compose/version"
require "dependabot/docker_compose/requirement"
require "dependabot/docker/update_checker"

module Dependabot
  module DockerCompose
    class UpdateChecker < Dependabot::Docker::UpdateChecker
    end
  end
end

Dependabot::UpdateCheckers.register(
  "docker_compose",
  Dependabot::DockerCompose::UpdateChecker
)
