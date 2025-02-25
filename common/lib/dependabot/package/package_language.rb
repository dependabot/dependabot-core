# typed: strong
# frozen_string_literal: true

# Represents a single package version
module Dependabot
  module Package
    class PackageLanguage
      extend T::Sig

      sig do
        params(
          name: String,
          version: T.nilable(Dependabot::Version),
          requirement: T.nilable(Dependabot::Requirement)
        ).void
      end
      def initialize(name:, version: nil, requirement: nil)
        @name = T.let(name, String)
        @version = T.let(version, T.nilable(Dependabot::Version))
        @requirement = T.let(requirement, T.nilable(Dependabot::Requirement))
      end

      sig { returns(String) }
      attr_reader :name

      sig { returns(T.nilable(Dependabot::Version)) }
      attr_reader :version

      sig { returns(T.nilable(Dependabot::Requirement)) }
      attr_reader :requirement
    end
  end
end
