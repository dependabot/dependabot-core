# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/composer/version"
require "dependabot/package_manager"

module Dependabot
  module Composer
    ECOSYSTEM = "composer"
    PACKAGE_MANAGER = "composer"

    SUPPORTED_COMPOSER_VERSIONS = T.let([Version.new("2")].freeze, T::Array[Dependabot::Version])
    DEPRECATED_COMPOSER_VERSIONS = T.let([Version.new("1")].freeze, T::Array[Dependabot::Version])

    class PackageManager < PackageManagerBase
      extend T::Sig

      sig { params(version: T.any(String, Dependabot::Version)).void }
      def initialize(version)
        super(
          ECOSYSTEM,
          PACKAGE_MANAGER,
          Version.new(version),
          DEPRECATED_COMPOSER_VERSIONS,
          SUPPORTED_COMPOSER_VERSIONS
        )
      end

      sig { override.returns(T::Boolean) }
      def unsupported?
        # Specific unsupported logic for Composer
        return false unless Dependabot::Experiments.enabled?(:composer_v1_unsupported_error)

        super # Call the `unsupported?` method from the super class.
      end

      sig { override.returns(T::Boolean) }
      def deprecated?
        # Specific deprecated logic for Composer
        return false unless Dependabot::Experiments.enabled?(:composer_v1_deprecation_warning)

        super # Call the `deprecated?` method from the super class.
      end
    end
  end
end
