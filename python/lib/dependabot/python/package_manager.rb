# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/python/version"
require "dependabot/ecosystem"
require "dependabot/python/requirement"

module Dependabot
  module Python
    ECOSYSTEM = "Python"

    SUPPORTED_PYTHON_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

    DEPRECATED_PYTHON_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

    class PipPackageManager < Dependabot::Ecosystem::VersionManager
      extend T::Sig

      NAME = "pip"

      SUPPORTED_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

      DEPRECATED_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

      sig do
        params(
          raw_version: String,
          requirement: T.nilable(Requirement)
        ).void
      end
      def initialize(raw_version, requirement = nil)
        super(
          name: NAME,
          version: Version.new(raw_version),
          deprecated_versions: DEPRECATED_VERSIONS,
          supported_versions: SUPPORTED_VERSIONS,
          requirement: requirement,
       )
      end

      sig { override.returns(T::Boolean) }
      def deprecated?
        false
      end

      sig { override.returns(T::Boolean) }
      def unsupported?
        false
      end
    end

    class PoetryPackageManager < Dependabot::Ecosystem::VersionManager
      extend T::Sig

      NAME = "poetry"

      LOCKFILE_NAME = "poetry.lock"

      SUPPORTED_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

      DEPRECATED_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

      sig do
        params(
          raw_version: String,
          requirement: T.nilable(Requirement)
        ).void
      end
      def initialize(raw_version, requirement = nil)
        super(
          name: NAME,
          version: Version.new(raw_version),
          deprecated_versions: DEPRECATED_VERSIONS,
          supported_versions: SUPPORTED_VERSIONS,
          requirement: requirement,
       )
      end

      sig { override.returns(T::Boolean) }
      def deprecated?
        false
      end

      sig { override.returns(T::Boolean) }
      def unsupported?
        false
      end

      # Poetry supports requires-poetry constraints in pyproject.toml;
      # other Python package managers don't have an equivalent mechanism.
      sig { override.void }
      def raise_if_unsupported!
        super
        return unless requirement
        return unless version
        return if T.must(requirement).satisfied_by?(T.must(version))

        raise Dependabot::ToolVersionNotSupported.new(
          NAME,
          version.to_s,
          requirement.to_s
        )
      end
    end

    class PipCompilePackageManager < Dependabot::Ecosystem::VersionManager
      extend T::Sig

      NAME = "pip-compile"
      MANIFEST_FILENAME = ".in"

      SUPPORTED_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

      DEPRECATED_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

      sig do
        params(
          raw_version: String,
          requirement: T.nilable(Requirement)
        ).void
      end
      def initialize(raw_version, requirement = nil)
        super(
          name: NAME,
          version: Version.new(raw_version),
          deprecated_versions: DEPRECATED_VERSIONS,
          supported_versions: SUPPORTED_VERSIONS,
          requirement: requirement,
       )
      end

      sig { override.returns(T::Boolean) }
      def deprecated?
        false
      end

      sig { override.returns(T::Boolean) }
      def unsupported?
        false
      end
    end

    class PipenvPackageManager < Dependabot::Ecosystem::VersionManager
      extend T::Sig

      NAME = "pipenv"

      MANIFEST_FILENAME = "Pipfile"
      LOCKFILE_FILENAME = "Pipfile.lock"

      SUPPORTED_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

      DEPRECATED_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

      sig do
        params(
          raw_version: String,
          requirement: T.nilable(Requirement)
        ).void
      end
      def initialize(raw_version, requirement = nil)
        super(
          name: NAME,
          version: Version.new(raw_version),
          deprecated_versions: DEPRECATED_VERSIONS,
          supported_versions: SUPPORTED_VERSIONS,
          requirement: requirement,
       )
      end

      sig { override.returns(T::Boolean) }
      def deprecated?
        false
      end

      sig { override.returns(T::Boolean) }
      def unsupported?
        false
      end
    end
  end
end
