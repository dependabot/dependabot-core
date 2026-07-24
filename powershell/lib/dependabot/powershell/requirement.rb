# typed: strict
# frozen_string_literal: true

require "dependabot/requirement"
require "dependabot/utils"

module Dependabot
  module Powershell
    class Requirement < Dependabot::Requirement
      extend T::Sig

      # A single PowerShell module specification maps to a single
      # requirement, which may itself carry multiple AND'd constraints
      # (e.g. ">= 1.0.0, <= 2.0.0" for a ModuleVersion/MaximumVersion range).
      # `nil` means the module was declared with no version constraint.
      sig do
        override
          .params(requirement_string: T.nilable(String))
          .returns(T::Array[Dependabot::Requirement])
      end
      def self.requirements_array(requirement_string)
        return [new] if requirement_string.nil?

        # Gem::Requirement (our superclass) can't parse a single string
        # containing multiple comma-separated constraints (e.g.
        # ">= 1.0.0, <= 2.0.0") - each constraint must be passed as its own
        # array element.
        constraints = requirement_string.split(",").map(&:strip)
        [new(constraints)]
      end
    end
  end
end

Dependabot::Utils
  .register_requirement_class("powershell", Dependabot::Powershell::Requirement)
