# typed: strict
# frozen_string_literal: true

module Dependabot
  module NpmAndYarn
    class BunPackageManager < Ecosystem::VersionManager
      extend T::Sig
      NAME = "bun"
      LOCKFILE_NAME = "bun.lock"

      # In Bun 1.1.39, the lockfile format was changed from a binary bun.lockb to a text-based bun.lock.
      # https://bun.sh/blog/bun-lock-text-lockfile
      MIN_SUPPORTED_VERSION = Version.new("1.1.39")
      SUPPORTED_VERSIONS = T.let([MIN_SUPPORTED_VERSION].freeze, T::Array[Dependabot::Version])
      DEPRECATED_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

      sig do
        params(
          detected_version: T.nilable(String),
          raw_version: T.nilable(String),
          requirement: T.nilable(Dependabot::NpmAndYarn::Requirement)
        ).void
      end
      def initialize(detected_version: nil, raw_version: nil, requirement: nil)
        super(
          name: NAME,
          detected_version: detected_version ? Version.new(detected_version) : nil,
          version: raw_version ? Version.new(raw_version) : nil,
          deprecated_versions: DEPRECATED_VERSIONS,
          supported_versions: SUPPORTED_VERSIONS,
          requirement: requirement
        )
      end

      sig { override.returns(T::Boolean) }
      def deprecated?
        false
      end

      sig { override.returns(T::Boolean) }
      def unsupported?
        supported_versions.all? { |supported| supported > version }
      end
    end
  end
end
