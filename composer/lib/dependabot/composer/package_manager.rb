# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/ecosystem"
require "dependabot/composer/version"

module Dependabot
  module Composer
    ECOSYSTEM = "composer"
    PACKAGE_MANAGER = "composer"

    # Keep versions in ascending order
    SUPPORTED_COMPOSER_VERSIONS = T.let([Version.new("2")].freeze, T::Array[Dependabot::Version])

    DEPRECATED_COMPOSER_VERSIONS = T.let([
      Version.new("1")
    ].freeze, T::Array[Dependabot::Version])

    class PackageManager < Dependabot::Ecosystem::VersionManager
      extend T::Sig

      sig { params(raw_version: String).void }
      def initialize(raw_version)
        super(
          PACKAGE_MANAGER,
          Version.new(raw_version),
          DEPRECATED_COMPOSER_VERSIONS,
          SUPPORTED_COMPOSER_VERSIONS,
       )
      end

      sig { override.returns(T::Boolean) }
      def deprecated?
        return false if unsupported?

        # Check if the feature flag for Composer v1 deprecation warning is enabled.
        return false unless Dependabot::Experiments.enabled?(:composer_v1_deprecation_warning)

        super
      end

      sig { override.returns(T::Boolean) }
      def unsupported?
        # Check if the feature flag for Composer v1 unsupported error is enabled.
        return false unless Dependabot::Experiments.enabled?(:composer_v1_unsupported_error)

        super
      end
    end
  end
end
