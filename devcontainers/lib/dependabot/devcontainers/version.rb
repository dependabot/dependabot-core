# typed: strong
# frozen_string_literal: true

require "dependabot/version"
require "dependabot/utils"

module Dependabot
  module Devcontainers
    class Version < Dependabot::Version
    end
  end
end

Dependabot::Utils.register_version_class("devcontainers", Dependabot::Devcontainers::Version)
