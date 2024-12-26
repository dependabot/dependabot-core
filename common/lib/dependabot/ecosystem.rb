# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/requirement"

module Dependabot
  class Ecosystem
    extend T::Sig

    class VersionManager
      extend T::Sig
      extend T::Helpers

      DEFAULT_VERSION_PATTERN = /(\d+\.\d+(.\d+)*)/

      abstract!
      # Initialize version information for a package manager or language.
      # @param name [String] the name of the package manager or language (e.g., "bundler", "ruby").
      # @param detected_version [Dependabot::Version] the detected version of the package manager or language.
      # @param version [Dependabot::Version] the version dependabots run on.
      # @param deprecated_versions [Array<Dependabot::Version>] an array of deprecated versions.
      # @param supported_versions [Array<Dependabot::Version>] an array of supported versions.
      # @param requirement [Dependabot::Requirement] an array of requirements.
      # @example
      #   VersionManager.new("bundler", "2.1.4", nil)
      sig do
        params(
          name: String,
          detected_version: T.nilable(Dependabot::Version),
          version: T.nilable(Dependabot::Version),
          deprecated_versions: T::Array[Dependabot::Version],
          supported_versions: T::Array[Dependabot::Version],
          requirement: T.nilable(Dependabot::Requirement)
        ).void
      end
      def initialize( # rubocop:disable Metrics/ParameterLists
        name,
        detected_version = nil,
        version = nil,
        deprecated_versions = [],
        supported_versions = [],
        requirement = nil
      )
        @name = T.let(name, String)
        @detected_version = T.let(detected_version, T.nilable(Dependabot::Version))
        @version = T.let(version, T.nilable(Dependabot::Version))
        @deprecated_versions = T.let(deprecated_versions, T::Array[Dependabot::Version])
        @supported_versions = T.let(supported_versions, T::Array[Dependabot::Version])
        @requirement = T.let(requirement, T.nilable(Dependabot::Requirement))
      end

      # The name of the package manager (e.g., "bundler", "npm").
      # @example
      #   name #=> "bundler"
      sig { returns(String) }
      attr_reader :name

      # The current version of the package manager or language.
      # @example
      #   version #=> Dependabot::Version.new("2")
      sig { returns(T.nilable(Dependabot::Version)) }
      attr_reader :detected_version

      # The current version of the package manager or language.
      # @example
      #   version #=> Dependabot::Version.new("2.1.4")
      sig { returns(T.nilable(Dependabot::Version)) }
      attr_reader :version

      # Returns an array of deprecated versions of the package manager.
      # @example
      #  deprecated_versions #=> [Version.new("1")]
      sig { returns(T::Array[Dependabot::Version]) }
      attr_reader :deprecated_versions

      # Returns an array of supported versions of the package manager.
      sig { returns(T::Array[Dependabot::Version]) }
      attr_reader :supported_versions

      # The current requirement of the package manager or language.
      # @example
      #  requirement #=> nil
      #  requirement #=> Dependabot::Requirement.new(">= 2.1.4")
      #  requirement #=> Dependabot::Requirement.new(">= 2.1.4, < 3.0")
      sig { returns(T.nilable(Dependabot::Requirement)) }
      attr_reader :requirement

      # Checks if the current version is deprecated.
      # Returns true if the version is in the deprecated_versions array; false otherwise.
      # @example
      #   deprecated? #=> true
      sig { returns(T::Boolean) }
      def deprecated?
        return false unless detected_version

        # If the version is unsupported, the unsupported error is getting raised separately.
        return false if unsupported?

        deprecated_versions.include?(detected_version)
      end

      # Checks if the current version is unsupported.
      # @example
      #   unsupported? #=> false
      sig { returns(T::Boolean) }
      def unsupported?
        return false unless detected_version

        return false if supported_versions.empty?

        # Check if the version is not supported
        supported_versions.all? { |supported| supported > detected_version }
      end

      # Raises an error if the current package manager or language version is unsupported.
      # If the version is unsupported, it raises a ToolVersionNotSupported error.
      sig { void }
      def raise_if_unsupported!
        return unless detected_version

        return unless unsupported?

        # Example: v2.*, v3.*
        supported_versions_message = supported_versions.map { |v| "v#{v}.*" }.join(", ")

        raise ToolVersionNotSupported.new(
          name,
          detected_version.to_s,
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

    # Initialize with mandatory name and optional language information.
    # @param name [String] the name of the ecosystem (e.g., "bundler", "npm_and_yarn").
    # @param package_manager [VersionManager] the package manager (mandatory).
    # @param language [VersionManager] the language (optional).
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
    #  package_manager #=> VersionManager.new("bundler", "2.1.4", deprecated_versions, supported_versions)
    sig { returns(VersionManager) }
    attr_reader :package_manager

    # The information related to the language (optional).
    # @example
    #  language #=> VersionManager.new("ruby", "3.9", deprecated_versions, supported_versions)
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
