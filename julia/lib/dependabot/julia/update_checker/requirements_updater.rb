# typed: strict
# frozen_string_literal: true

require "dependabot/julia/requirement"
require "dependabot/julia/version"

module Dependabot
  module Julia
    class RequirementsUpdater
      extend T::Sig

      sig do
        params(
          requirements: T::Array[T::Hash[Symbol, T.untyped]],
          target_version: T.nilable(String),
          update_strategy: T.nilable(Symbol)
        ).void
      end
      def initialize(requirements:, target_version:, update_strategy:)
        @requirements = requirements
        @target_version = target_version
        @update_strategy = T.let(update_strategy || :bump_versions, Symbol)
      end

      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def updated_requirements
        return requirements unless target_version

        target_version_obj = Dependabot::Julia::Version.new(target_version)

        requirements.map do |requirement|
          update_requirement(requirement, target_version_obj)
        end
      end

      private

      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      attr_reader :requirements

      sig { returns(T.nilable(String)) }
      attr_reader :target_version

      sig { returns(Symbol) }
      attr_reader :update_strategy

      sig do
        params(
          requirement: T::Hash[Symbol, T.untyped],
          target_version: Dependabot::Julia::Version
        ).returns(T::Hash[Symbol, T.untyped])
      end
      def update_requirement(requirement, target_version)
        current_requirement = requirement[:requirement]

        # If requirement is "*" or nil, use target version
        new_requirement = if current_requirement.nil? || current_requirement == "*"
                            target_version.to_s
                          else
                            updated_version_requirement(current_requirement, target_version)
                          end

        requirement.merge(requirement: new_requirement)
      end

      sig { params(requirement_string: String, target_version: Dependabot::Julia::Version).returns(String) }
      def updated_version_requirement(requirement_string, target_version)
        req = Dependabot::Julia::Requirement.new(requirement_string)

        # If current requirement already satisfied, keep it
        return requirement_string if req.satisfied_by?(target_version)

        # Otherwise, append a new requirement that includes the target version
        # Following CompatHelper.jl's approach: use major.minor for versions >= 1.0,
        # 0.minor for 0.x versions, and 0.0.patch for 0.0.x versions
        new_spec = simplified_version_spec(target_version, requirement_string)

        # Append the new spec to the existing requirement (CompatHelper KeepEntry behavior)
        "#{requirement_string}, #{new_spec}"
      end

      sig { params(target_version: Dependabot::Julia::Version, original_requirement: String).returns(String) }
      def simplified_version_spec(target_version, original_requirement)
        # Follow CompatHelper.jl's compat_version_number logic:
        # - major > 0: use "major.minor"
        # - major == 0, minor > 0: use "0.minor"
        # - major == 0, minor == 0: use "0.0.patch"
        # Note: CompatHelper always returns plain versions (no ^ or ~ prefix)
        major = target_version.segments[0]
        minor = target_version.segments[1] || 0
        patch = target_version.segments[2] || 0

        if major > 0
          "#{major}.#{minor}"
        elsif minor > 0
          "0.#{minor}"
        else
          "0.0.#{patch}"
        end
      end
    end
  end
end
