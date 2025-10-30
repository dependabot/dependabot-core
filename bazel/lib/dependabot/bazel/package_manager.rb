# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/bazel/version"
require "dependabot/ecosystem"
require "dependabot/bazel/requirement"

module Dependabot
  module Bazel
    ECOSYSTEM = "bazel"
    PACKAGE_MANAGER = "bazel"

    # Keep versions in ascending order
    SUPPORTED_BAZEL_VERSIONS = T.let([Version.new("6"), Version.new("7")].freeze, T::Array[Dependabot::Version])

    # Currently, we don't support any deprecated versions of Bazel
    # When a version is going to be unsupported, it will be added here for a while to give users time to upgrade
    DEPRECATED_BAZEL_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

    class PackageManager < Dependabot::Ecosystem::VersionManager
      extend T::Sig

      sig do
        params(
          detected_version: String,
          raw_version: T.nilable(String),
          requirement: T.nilable(Requirement)
        ).void
      end
      def initialize(detected_version:, raw_version: nil, requirement: nil)
        super(
          name: PACKAGE_MANAGER,
          detected_version: Version.new(detected_version),
          version: raw_version ? Version.new(raw_version) : nil,
          deprecated_versions: DEPRECATED_BAZEL_VERSIONS,
          supported_versions: SUPPORTED_BAZEL_VERSIONS,
          requirement: requirement
        )
      end
    end
  end
end
