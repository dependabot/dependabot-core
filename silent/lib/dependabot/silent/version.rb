# typed: strong
# frozen_string_literal: true

require "dependabot/version"
require "dependabot/utils"

module SilentPackageManager
  class Version < Dependabot::Version
  end
end

Dependabot::Utils
  .register_version_class("silent", SilentPackageManager::Version)
