# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency_requirement"
require "dependabot/powershell/requirement"
require "dependabot/powershell/version"

module Dependabot
  module Powershell
    class UpdateChecker
      # Rebuilds the `requirement` string for each of a dependency's
      # requirements so that it allows (and, where applicable, pins to) the
      # latest resolvable version - without changing how the requirement was
      # originally declared.
      #
      # The PowerShell file parser (stage 3) records which manifest
      # attribute(s) produced each requirement string via
      # `metadata[:version_key]`:
      #   - "RequiredVersion"             -> exact pin,        e.g. "= X"
      #   - "ModuleVersion"                -> minimum version,  e.g. ">= X"
      #   - "MaximumVersion"               -> maximum version,  e.g. "<= X"
      #   - "ModuleVersion+MaximumVersion" -> range,            e.g. ">= X, <= Y"
      #   - nil                            -> no constraint declared at all
      #
      # We preserve that shape (and therefore the declaration style the file
      # updater will need to reproduce) rather than switching a module over
      # to a different kind of constraint.
      class RequirementsUpdater
        extend T::Sig

        sig do
          params(
            requirements: T::Array[Dependabot::DependencyRequirement],
            latest_resolvable_version: T.nilable(T.any(String, Dependabot::Version))
          ).void
        end
        def initialize(requirements:, latest_resolvable_version:)
          @requirements = T.let(
            requirements.map { |req| Dependabot::DependencyRequirement.create(req) },
            T::Array[Dependabot::DependencyRequirement]
          )
          @latest_version = T.let(build_latest_version(latest_resolvable_version), T.nilable(Dependabot::Version))
        end

        sig { returns(T::Array[Dependabot::DependencyRequirement]) }
        def updated_requirements
          return requirements unless latest_version

          requirements.map { |requirement| updated_requirement(requirement) }
        end

        private

        sig { returns(T::Array[Dependabot::DependencyRequirement]) }
        attr_reader :requirements

        sig { returns(T.nilable(Dependabot::Version)) }
        attr_reader :latest_version

        sig do
          params(
            latest_resolvable_version: T.nilable(T.any(String, Dependabot::Version))
          ).returns(T.nilable(Dependabot::Version))
        end
        def build_latest_version(latest_resolvable_version)
          return nil if latest_resolvable_version.nil?
          return latest_resolvable_version if latest_resolvable_version.is_a?(Dependabot::Version)
          return nil unless Version.correct?(latest_resolvable_version)

          Version.new(latest_resolvable_version)
        end

        sig do
          params(requirement: Dependabot::DependencyRequirement).returns(Dependabot::DependencyRequirement)
        end
        def updated_requirement(requirement)
          requirement_string = requirement.requirement
          return requirement if requirement_string.nil? || requirement_string == :unfixable
          return requirement if satisfied_by_latest_version?(requirement_string)

          new_requirement_string = build_new_requirement_string(requirement_string, requirement.metadata)
          return requirement if new_requirement_string.nil? || new_requirement_string == requirement_string

          Dependabot::DependencyRequirement.create(requirement.merge(requirement: new_requirement_string))
        end

        sig { params(requirement_string: String).returns(T::Boolean) }
        def satisfied_by_latest_version?(requirement_string)
          Requirement.requirements_array(requirement_string).all? do |requirement|
            requirement.satisfied_by?(latest_version)
          end
        end

        sig do
          params(
            requirement_string: String,
            metadata: T.nilable(Dependabot::DependencyRequirement::ObjectHash)
          ).returns(T.nilable(String))
        end
        def build_new_requirement_string(requirement_string, metadata)
          version_key = metadata&.fetch(:version_key, nil)

          case version_key
          when "RequiredVersion"
            "= #{latest_version}"
          when "ModuleVersion"
            ">= #{latest_version}"
          when "MaximumVersion"
            "<= #{latest_version}"
          when "ModuleVersion+MaximumVersion"
            bump_range_maximum(requirement_string)
          end
        end

        # Raises the upper bound of a "ModuleVersion+MaximumVersion" range to
        # the latest resolvable version while leaving the declared lower
        # bound (ModuleVersion) untouched.
        sig { params(requirement_string: String).returns(T.nilable(String)) }
        def bump_range_maximum(requirement_string)
          constraints = requirement_string.split(",").map(&:strip)
          minimum_constraint = constraints.find { |constraint| constraint.start_with?(">=") }
          return nil unless minimum_constraint

          "#{minimum_constraint}, <= #{latest_version}"
        end
      end
    end
  end
end
