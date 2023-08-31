# frozen_string_literal: true

require "dependabot/version"
require "dependabot/utils"

module Dependabot
  module GitSubmodules
    class Version < Dependabot::Version
    end
  end
end

Dependabot::Utils.
  register_version_class("submodules", Dependabot::GitSubmodules::Version)
