# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  class Ecosystem
    extend T::Sig

    class VersionManager
      extend T::Sig
      extend T::Helpers

      abstract!
      # Initialize version information with optional requirement
      # @param name [String] the name for the package manager or language (e.g., "bundler", "ruby").
      # @param raw_version [String] the raw current version of the package manager or language.
      # @param version [Dependabot::Version] the parsed current version.
      # @param deprecated_versions [Array<Dependabot::Version>] an array of deprecated versions.
      # @param supported_versions [Array<Dependabot::Version>] an array of supported versions.
      # @param requirement [T.nilable(Requirement)] the version requirements, optional.
      # @example
      #   VersionManager.new("bundler", "2.1.4", Dependabot::Version.new("2.1.4"), nil)
      sig do
        params(
          name: String,
          raw_version: String,
          version: Dependabot::Version,
          deprecated_versions: T::Array[Dependabot::Version],
          supported_versions: T::Array[Dependabot::Version],
          requirement: T.nilable(Requirement)
        ).void
      end
      def initialize( # rubocop:disable Metrics/ParameterLists
        name,
        raw_version,
        version,
        deprecated_versions = [],
        supported_versions = [],
        requirement = nil
      )
        @name = T.let(name, String)
        @raw_version = T.let(raw_version, String)
        @version = T.let(version, Dependabot::Version)
        @requirement = T.let(requirement, T.nilable(Requirement))

        @deprecated_versions = T.let(deprecated_versions, T::Array[Dependabot::Version])
        @supported_versions = T.let(supported_versions, T::Array[Dependabot::Version])
      end

      # The name of the package manager or language (e.g., "bundler", "ruby").
      # @example
      #   name #=> "bundler"
      sig { returns(String) }
      attr_reader :name

      # The current version of the package manager or language.
      # @example
      #   version #=> Dependabot::Version.new("2.1.4")
      sig { returns(Dependabot::Version) }
      attr_reader :version

      # The raw current version of the package manager or language as a string.
      # @example
      #   raw_version #=> "2.1.4"
      sig { returns(String) }
      attr_reader :raw_version

      # The version requirements (optional).
      # @example
      #   requirement #=> Requirement.new(">= 2.1")
      sig { returns(T.nilable(Requirement)) }
      attr_reader :requirement

      # Returns an array of deprecated versions of the package manager.
      # @example
      #  deprecated_versions #=> [Version.new("1")]
      sig { returns(T::Array[Dependabot::Version]) }
      attr_reader :deprecated_versions

      # Returns an array of supported versions of the package manager.
      sig { returns(T::Array[Dependabot::Version]) }
      attr_reader :supported_versions

      # Checks if the current version is deprecated.
      # Returns true if the version is in the deprecated_versions array; false otherwise.
      # @example
      #   deprecated? #=> true
      sig { returns(T::Boolean) }
      def deprecated?
        return false if unsupported?

        deprecated_versions.include?(version)
      end

      # Checks if the current version is unsupported.
      # @example
      #   unsupported? #=> false
      sig { returns(T::Boolean) }
      def unsupported?
        return false if supported_versions.empty?

        # Check if the version is not supported
        supported_versions.all? { |supported| supported > version }
      end

      # Raises an error if the current package manager or language version is unsupported.
      # If the version is unsupported, it raises a ToolVersionNotSupported error.
      sig { void }
      def raise_if_unsupported!
        return unless unsupported?

        # Example: v2.*, v3.*
        supported_versions_message = supported_versions.map { |v| "v#{v}.*" }.join(", ")

        raise ToolVersionNotSupported.new(
          name,
          version.to_s,
          supported_versions_message
        )
      end

      # Indicates if the package manager supports later versions beyond those listed in supported_versions.
      # By default, returns false if not overridden in the subclass.
      # @example
      #   support_later_versions? #=> true
      sig { returns(T::Boolean) }
      def support_later_versions?
        false
      end
    end

    class Requirement
      extend T::Sig

      # Initialize version requirements with optional raw strings and parsed versions.
      # @param raw_constraint [T.nilable(String)] the raw version constraint (e.g., ">= 2.0").
      # @param min_raw_version [T.nilable(String)] the raw minimum version requirement (e.g., "2.0").
      # @param min_version [T.nilable(Dependabot::Version)] the parsed minimum version.
      # @param max_raw_version [T.nilable(String)] the raw maximum version requirement (e.g., "3.0").
      # @param max_version [T.nilable(Dependabot::Version)] the parsed maximum version.
      # @example
      #   Requirement.new(">= 2.0", "2.0", Version.new("2.0"), "3.0", Version.new("3.0"))
      sig do
        params(
          raw_constraint: T.nilable(String),
          min_raw_version: T.nilable(String),
          min_version: T.nilable(Dependabot::Version),
          max_raw_version: T.nilable(String),
          max_version: T.nilable(Dependabot::Version)
        ).void
      end
      def initialize(
        raw_constraint: nil,
        min_raw_version: nil,
        min_version: nil,
        max_raw_version: nil,
        max_version: nil
      )
        @raw_constraint = T.let(raw_constraint, T.nilable(String))
        @min_raw_version = T.let(min_raw_version, T.nilable(String))
        @min_version = T.let(min_version, T.nilable(Dependabot::Version))
        @max_raw_version = T.let(max_raw_version, T.nilable(String))
        @max_version = T.let(max_version, T.nilable(Dependabot::Version))
      end

      # The raw version constraint (e.g., ">= 2.0").
      sig { returns(T.nilable(String)) }
      attr_reader :raw_constraint

      # The raw minimum version requirement (e.g., "2.0").
      sig { returns(T.nilable(String)) }
      attr_reader :min_raw_version

      # The parsed minimum version.
      sig { returns(T.nilable(Dependabot::Version)) }
      attr_reader :min_version

      # The raw maximum version requirement (e.g., "3.0").
      sig { returns(T.nilable(String)) }
      attr_reader :max_raw_version

      # The parsed maximum version.
      sig { returns(T.nilable(Dependabot::Version)) }
      attr_reader :max_version
    end

    # Initialize with mandatory name and optional language information.
    # @param name [String] the name of the ecosystem (e.g., "bundler", "npm_and_yarn").
    # @param package_manager [VersionManager] the package manager.
    # @param language [T.nilable(VersionManager)] optional language version information.
    sig do
      params(
        name: String,
        package_manager: VersionManager,
        language: T.nilable(VersionManager)
      ).void
    end
    def initialize(
      name:,
      package_manager:,
      language: nil
    )
      @name = T.let(name, String)
      @package_manager = T.let(package_manager, VersionManager)
      @language = T.let(language, T.nilable(VersionManager))
    end

    # The name of the ecosystem (mandatory).
    # @example
    # name #=> "npm_and_yarn"
    sig { returns(String) }
    attr_reader :name

    # The information related to the package manager (mandatory).
    # @example
    #  package_manager #=> VersionManager.new("bundler", "2.1.4", Version.new("2.1.4"), nil)
    sig { returns(VersionManager) }
    attr_reader :package_manager

    # The version information of the language (optional).
    # @example
    # language #=> VersionManager.new("ruby", "3.0.0", Version.new("3.0.0"), nil)
    sig { returns(T.nilable(VersionManager)) }
    attr_reader :language

    # Checks if the current version is deprecated.
    # Returns true if the version is in the deprecated_versions array; false otherwise.
    sig { returns(T::Boolean) }
    def deprecated?
      package_manager.deprecated?
    end

    # Checks if the current version is unsupported.
    sig { returns(T::Boolean) }
    def unsupported?
      package_manager.unsupported?
    end

    # Delegate to the package manager to raise ToolVersionNotSupported if the version is unsupported.
    sig { void }
    def raise_if_unsupported!
      package_manager.raise_if_unsupported!
    end
  end
end
