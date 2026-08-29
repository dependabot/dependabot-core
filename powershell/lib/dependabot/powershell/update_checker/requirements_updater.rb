# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency_requirement"
require "dependabot/powershell/module_specification_version"
require "dependabot/powershell/requirement"
require "dependabot/powershell/update_checker"
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
          return requirement unless requirement_string.is_a?(String)

          raw_version_key = requirement.metadata&.fetch(:version_key, nil)
          version_key = raw_version_key.is_a?(String) ? raw_version_key : nil

          # A bare minimum-version constraint (ModuleVersion with no
          # MaximumVersion) is always "satisfied" by any newer version, so
          # the generic satisfied-by check below would leave it pinned to
          # its original floor forever. Skip that shortcut for this style
          # so the floor is bumped to track the latest resolvable version,
          # same as every other declaration style.
          if version_key != "ModuleVersion" &&
             satisfied_by_latest_version?(requirement_string, version_key)
            return requirement
          end

          new_requirement_string = build_new_requirement_string(requirement_string, requirement.metadata)
          return requirement if new_requirement_string.nil? || new_requirement_string == requirement_string

          Dependabot::DependencyRequirement.create(requirement.merge(requirement: new_requirement_string))
        end

        sig { params(requirement_string: String, version_key: T.nilable(String)).returns(T::Boolean) }
        def satisfied_by_latest_version?(requirement_string, version_key)
          native_result = module_specification_satisfaction(requirement_string, version_key)
          return native_result unless native_result.nil?

          Requirement.requirements_array(requirement_string).all? do |requirement|
            requirement.satisfied_by?(latest_version)
          end
        end

        sig do
          params(requirement_string: String, version_key: T.nilable(String)).returns(T.nilable(T::Boolean))
        end
        def module_specification_satisfaction(requirement_string, version_key)
          target = latest_version
          return unless target

          case version_key
          when "RequiredVersion"
            current = requirement_string.delete_prefix("=").strip
            comparison = ModuleSpecificationVersion.compare(target.to_s, current)
            comparison&.zero?
          when "MaximumVersion"
            current = requirement_string.delete_prefix("<=").strip
            comparison = ModuleSpecificationVersion.compare(target.to_s, current)
            return unless comparison

            comparison <= 0
          when "ModuleVersion+MaximumVersion"
            range_satisfaction(requirement_string, target.to_s)
          end
        end

        sig { params(requirement_string: String, target: String).returns(T.nilable(T::Boolean)) }
        def range_satisfaction(requirement_string, target)
          minimum_comparison = bound_comparison(requirement_string, ">=", target)
          maximum_comparison = bound_comparison(requirement_string, "<=", target)
          return unless minimum_comparison && maximum_comparison

          0.between?(maximum_comparison, minimum_comparison)
        end

        sig do
          params(requirement_string: String, operator: String, target: String).returns(T.nilable(Integer))
        end
        def bound_comparison(requirement_string, operator, target)
          constraint = requirement_string.split(",").map(&:strip).find { |item| item.start_with?(operator) }
          return unless constraint

          ModuleSpecificationVersion.compare(target, constraint.delete_prefix(operator).strip)
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
            bump_minimum(requirement_string)
          when "MaximumVersion"
            "<= #{latest_version}"
          when "ModuleVersion+MaximumVersion"
            bump_range_maximum(requirement_string)
          end
        end

        # Raises a bare minimum-version ("ModuleVersion") constraint to the
        # latest resolvable version, but only when that target is actually
        # greater than the declared floor. Because a minimum-only dependency
        # has no `dependency.version`, the latest-version finder does not
        # filter out releases below the declared floor - so if the declared
        # release is unlisted (e.g. the floor is `>= 2.0.0` but the Gallery's
        # latest listed release is `1.5.0`), blindly interpolating the
        # target here would open a requirement *downgrade*. Leave the floor
        # untouched in that case instead.
        sig { params(requirement_string: String).returns(T.nilable(String)) }
        def bump_minimum(requirement_string)
          current_minimum = requirement_string.delete_prefix(">=").strip
          return nil unless Version.correct?(current_minimum)

          target_version = latest_version
          return nil unless target_version && newer_than_declaration?(target_version, current_minimum)

          ">= #{target_version}"
        end

        # Raises the upper bound of a "ModuleVersion+MaximumVersion" range to
        # the latest resolvable version while leaving the declared lower
        # bound (ModuleVersion) untouched. Only does so when the latest
        # version actually exceeds the current upper bound - if the range is
        # merely unsatisfied because the latest version falls below the
        # declared lower bound, raising the upper bound to it as well would
        # produce an impossible range (e.g. `>= 2.0.0, <= 1.9.0`), so the
        # range is left unchanged in that case instead.
        sig { params(requirement_string: String).returns(T.nilable(String)) }
        def bump_range_maximum(requirement_string)
          constraints = requirement_string.split(",").map(&:strip)
          minimum_constraint = constraints.find { |constraint| constraint.start_with?(">=") }
          maximum_constraint = constraints.find { |constraint| constraint.start_with?("<=") }
          return nil unless minimum_constraint && maximum_constraint

          current_maximum = maximum_constraint.delete_prefix("<=").strip
          return nil unless Version.correct?(current_maximum)

          target_version = latest_version
          return nil unless target_version && newer_than_declaration?(target_version, current_maximum)

          "#{minimum_constraint}, <= #{target_version}"
        end

        sig { params(target: Dependabot::Version, declaration: String).returns(T::Boolean) }
        def newer_than_declaration?(target, declaration)
          comparison = ModuleSpecificationVersion.compare(target.to_s, declaration)
          return comparison.positive? if comparison

          target > Version.new(declaration)
        end
      end
    end
  end
end
