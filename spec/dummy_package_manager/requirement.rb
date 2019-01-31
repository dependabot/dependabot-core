# frozen_string_literal: true

require "dependabot/utils"

module DummyPackageManager
  class Requirement < Gem::Requirement
  end
end

Dependabot::Utils.
  register_requirement_class("dummy", DummyPackageManager::Requirement)
