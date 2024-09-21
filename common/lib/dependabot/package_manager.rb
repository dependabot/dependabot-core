# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  class PackageManagerBase
    extend T::Sig
    extend T::Helpers

    abstract!

    # The name of the package manager (e.g., "bundler").
    # @example
    #   package_manager.name #=> "bundler"
    sig { abstract.returns(String) }
    def name; end

    # The version of the package manager (e.g., Dependabot::Version.new("2.1.4")).
    # @example
    #   package_manager.version #=> Dependabot::Version.new("2.1.4")
    sig { abstract.returns(Dependabot::Version) }
    def version; end

    # Returns an array of deprecated versions of the package manager.
    # By default, returns an empty array if not overridden in the subclass.
    # @example
    #   package_manager.deprecated_versions #=> [Dependabot::Version.new("1.0.0"), Dependabot::Version.new("1.1.0")]
    sig { returns(T::Array[Dependabot::Version]) }
    def deprecated_versions
      []
    end

    # Returns an array of unsupported versions of the package manager.
    # By default, returns an empty array if not overridden in the subclass.
    # @example
    #   package_manager.unsupported_versions #=> [Dependabot::Version.new("0.9.0")]
    sig { returns(T::Array[Dependabot::Version]) }
    def unsupported_versions
      []
    end

    # Returns an array of supported versions of the package manager.
    # By default, returns an empty array if not overridden in the subclass.
    # @example
    #   package_manager.supported_versions #=> [Dependabot::Version.new("2.0.0"), Dependabot::Version.new("2.1.0")]
    sig { returns(T::Array[Dependabot::Version]) }
    def supported_versions
      []
    end

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
    # Returns true if the version is in the unsupported_versions array; false otherwise.
    # @example
    #   package_manager.unsupported? #=> false
    sig { returns(T::Boolean) }
    def unsupported?
      false
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
