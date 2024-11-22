# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/python/version"
require "dependabot/ecosystem"
require "dependabot/python/requirement"

module Dependabot
  module Python
    ECOSYSTEM = "Python"

    # Keep versions in ascending order
    SUPPORTED_PYTHON_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

    DEPRECATED_PYTHON_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

    class PackageManager < Dependabot::Ecosystem::VersionManager
      extend T::Sig

      sig do
        params(
          package_manager: String,
          raw_version: String,
          requirement: T.nilable(Requirement)
        ).void
      end
      def initialize(package_manager, raw_version, requirement = nil)
        super(
          package_manager,
          Version.new(raw_version),
          DEPRECATED_PYTHON_VERSIONS,
          SUPPORTED_PYTHON_VERSIONS,
          requirement,
       )
      end
    end
  end
end
