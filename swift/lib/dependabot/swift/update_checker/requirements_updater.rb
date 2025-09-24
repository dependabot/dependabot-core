# typed: strong
# frozen_string_literal: true

require "dependabot/update_checkers/base"
require "dependabot/swift/native_requirement"
require "dependabot/swift/version"

module Dependabot
  module Swift
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      class RequirementsUpdater
        extend T::Sig

        sig do
          params(
            requirements: T::Array[T::Hash[Symbol, T.untyped]],
            target_version: T.nilable(T.any(String, Gem::Version))
          ).void
        end
        def initialize(requirements:, target_version:)
          @requirements = requirements

          return unless target_version && Version.correct?(target_version)

          @target_version = T.let(Version.new(target_version), Dependabot::Version)
        end

        sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        def updated_requirements
          NativeRequirement.map_requirements(requirements) do |requirement|
            T.must(requirement.update_if_needed(T.must(target_version)))
          end
        end

        private

        sig { returns(T::Array[T.untyped]) }
        attr_reader :requirements

        sig { returns(T.nilable(Gem::Version)) }
        attr_reader :target_version
      end
    end
  end
end
