# typed: true
# frozen_string_literal: true

require "dependabot/requirement"
require "dependabot/utils"

module DummyPackageManager
  class Requirement < Dependabot::Requirement
    AND_SEPARATOR = /(?<=[a-zA-Z0-9*])\s+(?:&+\s+)?(?!\s*[|-])/

    def self.requirements_array(requirement_string)
      requirements = requirement_string.split(AND_SEPARATOR).map(&:strip)

      [new(*requirements)]
    end
  end
end

Dependabot::Utils
  .register_requirement_class("dummy", DummyPackageManager::Requirement)
