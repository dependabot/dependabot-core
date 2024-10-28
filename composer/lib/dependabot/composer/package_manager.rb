# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/package_manager"
require "dependabot/composer/version"

module Dependabot
  module Composer
    PACKAGE_MANAGER = "composer"

    # Keep versions in ascending order
    SUPPORTED_COMPOSER_VERSIONS = T.let([Version.new("2")].freeze, T::Array[Dependabot::Version])

    DEPRECATED_COMPOSER_VERSIONS = T.let([
      Version.new("1")
    ].freeze, T::Array[Dependabot::Version])

    class PackageManager < PackageManagerBase
      extend T::Sig

      sig { params(version: T.any(String, Dependabot::Version)).void }
      def initialize(version)
        @version = T.let(Version.new(version), Dependabot::Version)
        @name = T.let(PACKAGE_MANAGER, String)
        @deprecated_versions = T.let(DEPRECATED_COMPOSER_VERSIONS, T::Array[Dependabot::Version])
        @supported_versions = T.let(SUPPORTED_COMPOSER_VERSIONS, T::Array[Dependabot::Version])
      end

      sig { override.returns(String) }
      attr_reader :name

      sig { override.returns(Dependabot::Version) }
      attr_reader :version

      sig { override.returns(T::Array[Dependabot::Version]) }
      attr_reader :deprecated_versions

      sig { override.returns(T::Array[Dependabot::Version]) }
      attr_reader :supported_versions

      sig { override.returns(T::Boolean) }
      def deprecated?
        return false if unsupported?

        # Check if the feature flag for Composer v1 deprecation warning is enabled.
        return false unless Dependabot::Experiments.enabled?(:composer_v1_deprecation_warning)

        deprecated_versions.include?(version)
      end

      sig { override.returns(T::Boolean) }
      def unsupported?
        # Check if the feature flag for Composer v1 unsupported error is enabled.
        return false unless Dependabot::Experiments.enabled?(:composer_v1_unsupported_error)

        supported_versions.all? { |supported| supported > version }
      end
    end
  end
end
