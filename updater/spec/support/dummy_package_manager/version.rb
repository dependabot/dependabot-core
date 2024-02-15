# typed: true
# frozen_string_literal: true

require "dependabot/version"
require "dependabot/utils"

module DummyPackageManager
  class Version < Dependabot::Version
  end
end

Dependabot::Utils
  .register_version_class("dummy", DummyPackageManager::Version)
