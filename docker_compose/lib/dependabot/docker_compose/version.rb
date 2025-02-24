# typed: strict
# frozen_string_literal: true

require "dependabot/utils"
require "dependabot/docker/version"

Dependabot::Utils
  .register_version_class("docker_compose", Dependabot::Docker::Version)
