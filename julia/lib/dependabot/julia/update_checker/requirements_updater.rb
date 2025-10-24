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

        # Otherwise, create a new requirement that includes the target version
        if requirement_string.start_with?("^")
          # Caret requirement: ^1.2 -> update to ^new_major.new_minor if needed
          "^#{target_version.segments[0]}.#{target_version.segments[1] || 0}"
        elsif requirement_string.start_with?("~")
          # Tilde requirement: ~1.2.3 -> update to ~new_version
          "~#{target_version}"
        elsif requirement_string.include?("-")
          # Range requirement: keep as is or expand to include target
          requirement_string
        else
          # Exact version or other: use target version
          target_version.to_s
        end
      end
    end
  end
end
