# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/elm/version"
require "dependabot/ecosystem"
require "dependabot/elm/requirement"

module Dependabot
  module Elm
    ECOSYSTEM = "elm"
    PACKAGE_MANAGER = "elm"
    ELM_VERSION_KEY = "elm-version"
    MANIFEST_FILE = "elm.json"
    DEFAULT_ELM_VERSION = "0.19.0"

    # Keep versions in ascending order
    SUPPORTED_ELM_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

    # Currently, we don't support any deprecated versions of Elm
    # When a version is going to be unsupported, it will be added here for a while to give users time to upgrade
    # Example for deprecation:
    # DEPRECATED_ELM_VERSIONS = T.let([Version.new("1")].freeze, T::Array[Dependabot::Version])
    DEPRECATED_ELM_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

    class PackageManager < Dependabot::Ecosystem::VersionManager
      extend T::Sig

      sig do
        params(
          raw_version: T.nilable(String),
          requirement: T.nilable(Requirement)
        ).void
      end
      def initialize(raw_version, requirement = nil)
        super(
          PACKAGE_MANAGER,
          nil,
          raw_version ? Version.new(raw_version) : nil,
          DEPRECATED_ELM_VERSIONS,
          SUPPORTED_ELM_VERSIONS,
          requirement,
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
