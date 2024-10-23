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
      # @param name [String] the name of the package manager or language (e.g., "bundler", "ruby").
      # @param raw_version [String] the raw current version of the package manager or language.
      # @param version [Dependabot::Version] the parsed current version.
      # @param deprecated_versions [Array<Dependabot::Version>] an array of deprecated versions.
      # @param supported_versions [Array<Dependabot::Version>] an array of supported versions.
      # @param requirement [T.nilable(Requirement)] the version requirements, optional.
      # @example
      #   VersionInformation.new("bundler", "2.1.4", Dependabot::Version.new("2.1.4"), nil)
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
      #   version_information.name #=> "bundler"
      sig { returns(String) }
      attr_reader :name

      # The current version of the package manager or language.
      # @example
      #   version_information.version #=> Dependabot::Version.new("2.1.4")
      sig { returns(Dependabot::Version) }
      attr_reader :version

      # The raw current version of the package manager or language as a string.
      # @example
      #   version_information.raw_version #=> "2.1.4"
      sig { returns(String) }
      attr_reader :raw_version

      # The version requirements (optional).
      # @example
      #   version_information.requirement #=> Requirement.new(">= 2.1")
      sig { returns(T.nilable(Ecosystem::Requirement)) }
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
      #   package_manager.deprecated? #=> true
      sig { returns(T::Boolean) }
      def deprecated?
        # If the version is unsupported, the unsupported error is getting raised separately.
        return false if unsupported?

        deprecated_versions.include?(version)
      end

      # Checks if the current version is unsupported.
      # @example
      #   package_manager.unsupported? #=> false
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
      #   package_manager.support_later_versions? #=> true
      sig { returns(T::Boolean) }
      def support_later_versions?
        false
      end
    end

    class Requirement
      extend T::Sig

      # Initialize version requirements with optional raw strings and parsed versions.
      # @param req_raw [T.nilable(String)] the raw version requirements.
      # @param req_raw_min [T.nilable(String)] the raw minimum version requirement.
      # @param req_min [T.nilable(Dependabot::Version)] the parsed minimum version requirement.
      # @param req_raw_max [T.nilable(String)] the raw maximum version requirement.
      # @param req_max [T.nilable(Dependabot::Version)] the parsed maximum version requirement.
      # @example
      #   Requirement.new(">= 2.0", "2.0", Version.new("2.0"), "3.0", Version.new("3.0"))
      sig do
        params(
          req_raw: T.nilable(String),
          req_raw_min: T.nilable(String),
          req_min: T.nilable(Dependabot::Version),
          req_raw_max: T.nilable(String),
          req_max: T.nilable(Dependabot::Version)
        ).void
      end
      def initialize(
        req_raw,
        req_raw_min,
        req_min,
        req_raw_max,
        req_max
      )
        # Ensure the type is correctly assigned to nullable types
        @req_raw = T.let(req_raw, T.nilable(String))
        @req_raw_min = T.let(req_raw_min, T.nilable(String))
        @req_min = T.let(req_min, T.nilable(Dependabot::Version)) # Correctly inferred as nilable version
        @req_raw_max = T.let(req_raw_max, T.nilable(String))
        @req_max = T.let(req_max, T.nilable(Dependabot::Version)) # Correctly inferred as nilable version
      end

      # The raw version requirement.
      sig { returns(T.nilable(String)) }
      attr_reader :req_raw

      # The raw minimum version requirement.
      sig { returns(T.nilable(String)) }
      attr_reader :req_raw_min

      # The parsed minimum version requirement.
      sig { returns(T.nilable(Dependabot::Version)) }
      attr_reader :req_min

      # The raw maximum version requirement.
      sig { returns(T.nilable(String)) }
      attr_reader :req_raw_max

      # The parsed maximum version requirement.
      sig { returns(T.nilable(Dependabot::Version)) }
      attr_reader :req_max
    end

    # Initialize with mandatory ecosystem and optional language information.
    # @param ecosystem [String] the name of the ecosystem (e.g., "bundler", "npm_and_yarn").
    # @param package_managers [VersionManager] the package manager
    # @param language [T.nilable(VersionManager)] optional language version information.
    sig do
      params(
        ecosystem: String,
        package_managers: T::Array[VersionManager],
        language: T.nilable(VersionManager)
      ).void
    end
    def initialize(
      ecosystem,
      package_managers,
      language = nil
    )
      @ecosystem = T.let(ecosystem, String)
      @package_managers = T.let(package_managers, T::Array[VersionManager])
      @language = T.let(language, T.nilable(VersionManager))
    end

    # The name of the ecosystem (mandatory).
    # @example
    # ecosystem #=> "npm_and_yarn"
    sig { returns(String) }
    attr_reader :ecosystem

    # The version information of the language (optional).
    # @example
    # language #=> VersionInformation.new("ruby", "3.0.0", Version.new("3.0.0"), nil)
    sig { returns(T.nilable(VersionManager)) }
    attr_reader :language

    # The version information of the package manager.
    # @example
    #  package_manager #=> VersionInformation.new("bundler", "2.1.4", Version.new("2.1.4"), nil)
    sig { returns(T::Array[VersionManager]) }
    attr_reader :package_managers

    # Checks if the current version is deprecated.
    # Returns true if the version is in the deprecated_versions array; false otherwise.
    # @example
    #   package_manager.deprecated? #=> true
    sig { returns(T::Boolean) }
    def deprecated?
      # If there is no package manager information, return false
      return false if package_managers.empty?

      # If the version is unsupported, the unsupported error is getting raised separately.
      return false if package_managers.any?(&:unsupported?)

      package_managers.any?(&:deprecated?)
    end

    # Checks if the current version is unsupported.
    # @example
    #   package_manager.unsupported? #=> false
    sig { returns(T::Boolean) }
    def unsupported?
      # If there is no package manager information, return false
      return false if package_managers.empty?

      # if any of the package managers are unsupported, return unsupported true
      package_managers.any?(&:unsupported?)
    end

    # Raises an error if the current package manager version is unsupported.
    # If the version is unsupported, it raises a ToolVersionNotSupported error.
    sig { void }
    def raise_if_unsupported!
      return unless unsupported?

      # If any of the package managers are unsupported, raise an error
      package_managers.each(&:raise_if_unsupported!)
    end
  end
end
