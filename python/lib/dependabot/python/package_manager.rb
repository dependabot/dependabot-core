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
          detected_version: String,
          raw_version: String,
          requirement: T.nilable(Requirement)
        ).void
      end
      def initialize(detected_version, raw_version, requirement = nil)
        super(
          NAME,
          Version.new(detected_version),
          Version.new(raw_version),
          SUPPORTED_VERSIONS,
          DEPRECATED_VERSIONS,
          requirement,
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
          detected_version: String,
          raw_version: String,
          requirement: T.nilable(Requirement)
        ).void
      end
      def initialize(detected_version, raw_version, requirement = nil)
        super(
          NAME,
          Version.new(detected_version),
          Version.new(raw_version),
          SUPPORTED_VERSIONS,
          DEPRECATED_VERSIONS,
          requirement,
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

    class PipCompilePackageManager < Dependabot::Ecosystem::VersionManager
      extend T::Sig

      NAME = "pip-compile"

      SUPPORTED_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

      DEPRECATED_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

      sig do
        params(
          detected_version: String,
          raw_version: String,
          requirement: T.nilable(Requirement)
        ).void
      end
      def initialize(detected_version, raw_version, requirement = nil)
        super(
          NAME,
          Version.new(detected_version),
          Version.new(raw_version),
          SUPPORTED_VERSIONS,
          DEPRECATED_VERSIONS,
          requirement,
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
          detected_version: String,
          raw_version: String,
          requirement: T.nilable(Requirement)
        ).void
      end
      def initialize(detected_version, raw_version, requirement = nil)
        super(
          NAME,
          Version.new(detected_version),
          Version.new(raw_version),
          SUPPORTED_VERSIONS,
          DEPRECATED_VERSIONS,
          requirement,
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
