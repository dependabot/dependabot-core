# typed: strict
# frozen_string_literal: true

require "dependabot/requirement"
require "dependabot/utils"
require "dependabot/powershell/version"

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

      # Gem::Requirement#initialize calls .parse on each requirement string
      # and stores the resulting [operator, Gem::Version] pairs. Left to the
      # default implementation, those pairs hold plain Gem::Version instances
      # rather than Powershell::Version, so Gem::Requirement#satisfied_by?
      # compares using Gem::Version#== - which normalizes prerelease
      # segments (e.g. "5.5.0-beta1" becomes "5.5.0.pre.beta1") and would
      # never match the release it names via `= 5.5.0-beta1`. Overriding
      # `.parse` to build Powershell::Version operands instead routes those
      # comparisons through Powershell::Version#==, which preserves the
      # original string form.
      sig do
        params(obj: T.any(String, Gem::Version))
          .returns(T::Array[T.any(String, Gem::Version)])
      end
      def self.parse(obj)
        return ["=", Powershell::Version.new(obj.to_s)] if obj.is_a?(Gem::Version)

        unless (matches = PATTERN.match(obj.to_s))
          msg = "Illformed requirement [#{obj.inspect}]"
          raise BadRequirementError, msg
        end

        return DefaultRequirement if matches[1] == ">=" && matches[2] == "0"

        [matches[1] || "=", Powershell::Version.new(T.must(matches[2]))]
      end
    end
  end
end

Dependabot::Utils
  .register_requirement_class("powershell", Dependabot::Powershell::Requirement)
