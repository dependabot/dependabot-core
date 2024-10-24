# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  class PackageManagerBase
    extend T::Sig
    extend T::Helpers

    abstract!

    # Initialize common attributes for all package managers
    # @param ecosystem [String] the name of the ecosystem (e.g., "npm_and_yarn", "composer").
    # @param name [String] the name of the package manager (e.g., "npm", "bundler").
    # @param raw_version [String] the version of the package manager (e.g., "6.0.0").
    # @param version [Dependabot::Version] the version of the package manager Version.new("1.0.0").
    # @param deprecated_versions [Array<Dependabot::Version>] an array of deprecated versions.
    # @param supported_versions [Array<Dependabot::Version>] an array of supported versions.
    sig do
      params(
        ecosystem: String,
        name: String,
        raw_version: String,
        version: Dependabot::Version,
        deprecated_versions: T::Array[Dependabot::Version],
        supported_versions: T::Array[Dependabot::Version]
      ).void
    end
    def initialize( # rubocop:disable Metrics/ParameterLists
      ecosystem,
      name,
      raw_version,
      version,
      deprecated_versions = [],
      supported_versions = []
    )
      @ecosystem = T.let(ecosystem, String)
      @name = T.let(name, String)
      @raw_version = T.let(raw_version, String)
      @version = T.let(version, Dependabot::Version)
      @deprecated_versions = T.let(deprecated_versions, T::Array[Dependabot::Version])
      @supported_versions = T.let(supported_versions, T::Array[Dependabot::Version])
    end

    # The name of the ecosystem (e.g., "npm_and_yarn", "composer").
    # @example
    #   package_manager.ecosystem #=> "npm_and_yarn"
    sig { returns(String) }
    attr_reader :ecosystem

    # The name of the package manager (e.g., "npm", "bundler").
    # @example
    #   package_manager.name #=> "npm"
    sig { returns(String) }
    attr_reader :name

    # The version of the package manager (e.g., "6.0.0").
    # @example
    #   package_manager.version #=> "6.0.0"
    sig { returns(String) }
    attr_reader :raw_version

    # The version of the package manager (e.g., "6.0.0").
    # @example
    #   package_manager.version #=> "6.0.0"
    sig { returns(Dependabot::Version) }
    attr_reader :version

    # Returns an array of deprecated versions of the package manager.
    # @example
    #   package_manager.deprecated_versions #=> [Dependabot::Version.new("1.0.0"), Dependabot::Version.new("1.1.0")]
    sig { returns(T::Array[Dependabot::Version]) }
    attr_reader :deprecated_versions

    # Returns an array of supported versions of the package manager.
    # @example
    #   package_manager.supported_versions #=> [Dependabot::Version.new("2.0.0"), Dependabot::Version.new("2.1.0")]
    sig { returns(T::Array[Dependabot::Version]) }
    attr_reader :supported_versions

    # Checks if the current version is deprecated.
    # @example
    #   package_manager.deprecated? #=> true
    sig { returns(T::Boolean) }
    def deprecated?
      # If the version is unsupported, the unsupported error is getting raised separately.
      return false if unsupported?

      deprecated_versions.include?(version)
    end

    # Checks if the current version is unsupported.
    # Returns true if the version lower then all supported versions.
    # @example
    #   package_manager.unsupported? #=> false
    sig { returns(T::Boolean) }
    def unsupported?
      # If there is no defined supported_versions, we assume that all versions are supported
      return false if supported_versions.empty?

      # Check if the version is not supported
      supported_versions.all? { |supported| supported > version }
    end

    # Raises an error if the current package manager version is unsupported.
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
end
