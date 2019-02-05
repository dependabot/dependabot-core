# frozen_string_literal: true

require "dependabot/utils"

module DummyPackageManager
  class Version < Gem::Version
  end
end

Dependabot::Utils.
  register_version_class("dummy", DummyPackageManager::Version)
