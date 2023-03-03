# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/ecosystem"
require "dependabot/maven/version"
require "dependabot/maven/requirement"

module Dependabot
  module Maven
    ECOSYSTEM = "maven"
    PACKAGE_MANAGER = "maven"

    # Supported versions specified here: https://maven.apache.org/docs/history.html
    SUPPORTED_MAVEN_VERSIONS = T.let([Version.new("3")].freeze, T::Array[Dependabot::Version])

    # When a version is going to be unsupported, it will be added here
    DEPRECATED_MAVEN_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

    class PackageManager < Dependabot::Ecosystem::VersionManager
      extend T::Sig

      sig do
        params(
          raw_version: String,
          requirement: T.nilable(Requirement)
        ).void
      end
      def initialize(raw_version, requirement = nil)
        super(
          name: PACKAGE_MANAGER,
          version: Version.new(raw_version),
          deprecated_versions: DEPRECATED_MAVEN_VERSIONS,
          supported_versions: SUPPORTED_MAVEN_VERSIONS,
          requirement: requirement,
        )
      end

      sig { returns(T::Boolean) }
      def deprecated?
        false
      end

      sig { returns(T::Boolean) }
      def unsupported?
        false
      end
    end
  end
end
