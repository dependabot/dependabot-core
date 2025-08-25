# typed: strict
# frozen_string_literal: true

require "dependabot/registry_client"

module Dependabot
  module Gradle
    module Distributions
      extend T::Sig

      DISTRIBUTIONS_URL = "https://services.gradle.org"
      DISTRIBUTION_DEPENDENCY_TYPE = "gradle-distribution"

      sig { params(requirements: T::Array[T::Hash[Symbol, T.untyped]]).returns(T::Boolean) }
      def self.distribution_requirements?(requirements)
        requirements.any? do |req|
          req.dig(:source, :type) == DISTRIBUTION_DEPENDENCY_TYPE
        end
      end
    end
  end
end
