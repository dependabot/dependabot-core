# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/ecosystem"
require "dependabot/pre_commit/version"

module Dependabot
  module PreCommit
    ECOSYSTEM = "pre_commit"
    PACKAGE_MANAGER = "pre_commit"
    SUPPORTED_PRE_COMMIT_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

    DEPRECATED_PRE_COMMIT_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

    class PackageManager < Dependabot::Ecosystem::VersionManager
      extend T::Sig

      sig { params(raw_version: String).void }
      def initialize(raw_version)
        super(
          name: PACKAGE_MANAGER,
          version: Version.new(raw_version),
          deprecated_versions: DEPRECATED_PRE_COMMIT_VERSIONS,
          supported_versions: SUPPORTED_PRE_COMMIT_VERSIONS
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
