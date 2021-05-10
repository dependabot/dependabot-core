# frozen_string_literal: true

require "dependabot/utils"

module DummyPackageManager
  class Requirement < Gem::Requirement
    def self.requirements_array(requirement_string)
      [new(requirement_string)]
    end

    # Patches Gem::Requirement to make it accept requirement strings like
    # "~> 4.2.5, >= 4.2.5.1" without first needing to split them.
    def initialize(*requirements)
      requirements = requirements.flatten.flat_map do |req_string|
        req_string.split(",").map(&:strip)
      end

      super(requirements)
    end
  end
end

Dependabot::Utils.
  register_requirement_class("dummy", DummyPackageManager::Requirement)
