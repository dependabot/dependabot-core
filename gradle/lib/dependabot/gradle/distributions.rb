# typed: strict
# frozen_string_literal: true

require "dependabot/dependency_requirement"

module Dependabot
  module Gradle
    module Distributions
      extend T::Sig

      DISTRIBUTION_REPOSITORY_URL = "https://services.gradle.org"
      DISTRIBUTION_DEPENDENCY_TYPE = "gradle-distribution"

      sig { params(requirements: T::Array[Dependabot::DependencyRequirement]).returns(T::Boolean) }
      def self.distribution_requirements?(requirements)
        requirements.any? do |req|
          req.source&.[](:type) == DISTRIBUTION_DEPENDENCY_TYPE
        end
      end
    end
  end
end
