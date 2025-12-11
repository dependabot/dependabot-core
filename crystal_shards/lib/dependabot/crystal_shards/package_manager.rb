# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/crystal_shards/version"
require "dependabot/ecosystem"
require "dependabot/crystal_shards/requirement"

module Dependabot
  module CrystalShards
    ECOSYSTEM = "crystal_shards"
    PACKAGE_MANAGER = "shards"
    MANIFEST_FILE = "shard.yml"
    LOCKFILE = "shard.lock"
    DEFAULT_SHARDS_VERSION = "0.18.0"

    SUPPORTED_SHARDS_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])
    DEPRECATED_SHARDS_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

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
          deprecated_versions: DEPRECATED_SHARDS_VERSIONS,
          supported_versions: SUPPORTED_SHARDS_VERSIONS,
          requirement: requirement
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
