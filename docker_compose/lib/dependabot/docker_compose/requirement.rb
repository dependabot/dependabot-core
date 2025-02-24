# typed: strong
# frozen_string_literal: true

require "dependabot/utils"
require "dependabot/docker/requirement"

Dependabot::Utils
  .register_requirement_class("docker_compose", Dependabot::Docker::Requirement)
