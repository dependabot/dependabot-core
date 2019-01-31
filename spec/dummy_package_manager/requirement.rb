# frozen_string_literal: true

require "dependabot/utils"

module DummyPackageManager
  class Requirement < Gem::Requirement
    def self.requirements_array(requirement_string)
      [new(requirement_string)]
    end
  end
end

Dependabot::Utils.
  register_requirement_class("dummy", DummyPackageManager::Requirement)
