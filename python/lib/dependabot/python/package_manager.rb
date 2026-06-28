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

      POETRY_V1 = "1"
      POETRY_V2 = "2"

      # Keep versions in ascending order
      SUPPORTED_VERSIONS = T.let(
        [
          Version.new(POETRY_V1),
          Version.new(POETRY_V2)
        ].freeze,
        T::Array[Dependabot::Version]
      )

      DEPRECATED_VERSIONS = T.let([Version.new(POETRY_V1)].freeze, T::Array[Dependabot::Version])

      sig do
        params(
          raw_version: String,
          requirement: T.nilable(Requirement)
        ).void
      end
      def initialize(raw_version, requirement = nil)
        version = Version.new(raw_version)
        super(
          name: NAME,
          detected_version: Version.new(T.must(version.segments.first).to_s),
          version: version,
          deprecated_versions: DEPRECATED_VERSIONS,
          supported_versions: SUPPORTED_VERSIONS,
          requirement: requirement,
       )
      end

      # Poetry supports requires-poetry constraints in pyproject.toml;
      # other Python package managers don't have an equivalent mechanism.
      sig { override.void }
      def raise_if_unsupported!
        super
        return unless requirement
        return unless version
        return if T.cast(T.must(requirement).satisfied_by?(T.must(version)), T::Boolean)

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
