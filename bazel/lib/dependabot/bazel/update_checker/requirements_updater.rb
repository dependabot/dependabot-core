# typed: strong
# frozen_string_literal: true

require "dependabot/dependency_requirement"
require "dependabot/bazel/update_checker"

module Dependabot
  module Bazel
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      class RequirementsUpdater
        extend T::Sig

        sig { params(requirements: T::Array[Dependabot::DependencyRequirement], latest_version: String).void }
        def initialize(requirements:, latest_version:)
          @requirements = T.let(
            requirements,
            T::Array[Dependabot::DependencyRequirement]
          )
          @latest_version = latest_version
        end

        sig { returns(T::Array[Dependabot::DependencyRequirement]) }
        def updated_requirements
          @requirements.map { |requirement| requirement.with_requirement(@latest_version) }
        end

        private

        sig { returns(T::Array[Dependabot::DependencyRequirement]) }
        attr_reader :requirements

        sig { returns(String) }
        attr_reader :latest_version
      end
    end
  end
end
