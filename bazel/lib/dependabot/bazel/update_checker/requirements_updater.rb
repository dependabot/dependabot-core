# typed: strong
# frozen_string_literal: true

require "dependabot/bazel/update_checker"

module Dependabot
  module Bazel
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      class RequirementsUpdater
        extend T::Sig

        sig { params(requirements: T::Array[T::Hash[Symbol, T.untyped]], latest_version: String).void }
        def initialize(requirements:, latest_version:)
          @requirements = requirements
          @latest_version = latest_version
        end

        sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        def updated_requirements
          @requirements.map do |requirement|
            updated_requirement = requirement.dup
            updated_requirement[:requirement] = @latest_version
            updated_requirement
          end
        end

        private

        sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        attr_reader :requirements

        sig { returns(String) }
        attr_reader :latest_version
      end
    end
  end
end
