# frozen_string_literal: true

require "dependabot/utils"

module Dependabot
  module Docker
    class Version < Gem::Version
    end
  end
end

Dependabot::Utils.
  register_version_class("docker", Dependabot::Docker::Version)
