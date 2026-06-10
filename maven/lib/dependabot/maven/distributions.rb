# typed: strict
# frozen_string_literal: true

module Dependabot
  module Maven
    module Distributions
      extend T::Sig

      # Used to distinguish wrapper requirements (which live in maven-wrapper.properties)
      # from regular POM requirements (which live in pom.xml)
      DISTRIBUTION_DEPENDENCY_TYPE = "maven-distribution"

      # Maven and the maven-wrapper plugin release independently with separate cadences.
      # Tracking them as distinct dependencies allows users to update each on their own
      # schedule. Users who prefer batched updates can use grouped updates.

      MAVEN_DISTRIBUTION_PACKAGE = "org.apache.maven:apache-maven"
      MAVEN_WRAPPER_PACKAGE      = "org.apache.maven.wrapper:maven-wrapper"

      sig { params(requirements: T::Array[T::Hash[Symbol, T.untyped]]).returns(T::Boolean) }
      def self.distribution_requirements?(requirements)
        # Returns true if any requirement came from a maven-wrapper.properties
        # file rather than a pom.xml. Used as the primary guard throughout the
        # updater pipeline to short-circuit non-wrapper paths.
        requirements.any? { |req| req.dig(:source, :type) == DISTRIBUTION_DEPENDENCY_TYPE }
      end
    end
  end
end
