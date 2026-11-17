# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/errors"
require "dependabot/npm_and_yarn/constraint_helper"
require "dependabot/npm_and_yarn/helpers"
require "dependabot/npm_and_yarn/npm_package_manager"

module Dependabot
  module NpmAndYarn
    # npm 12 dropped npm-shrinkwrap.json support, so a project with a shrinkwrap can only be updated with npm 11
    # or lower. Where the project's declared npm version allows it we stay on a compatible version; otherwise the
    # configuration is incompatible and we fail with a clear error rather than ignore the lockfile or the declared
    # constraint.
    module ShrinkwrapCompatibility
      extend T::Sig

      FEATURE = T.let("npm-shrinkwrap.json with npm #{Helpers::NPM_V12} or higher".freeze, String)

      # The npm version to use for an `engines.npm` selection, capped at the newest npm that supports shrinkwrap.
      sig { params(engines_constraint: T.nilable(String), selected_version: String).returns(String) }
      def self.engines_version(engines_constraint, selected_version)
        return selected_version unless incompatible_version?(selected_version)

        compatible = ConstraintHelper.find_highest_version_from_constraint_expression(
          engines_constraint, compatible_supported_versions
        )
        raise_unsupported! if compatible.nil? || incompatible_version?(compatible)

        compatible
      end

      # An explicit npm pin (e.g. `packageManager: npm@12.1.0`) can't be adjusted, so it must already be compatible.
      sig { params(version: String).void }
      def self.ensure_pin_supported!(version)
        raise_unsupported! if incompatible_version?(version)
      end

      sig { params(version: String).returns(T::Boolean) }
      def self.incompatible_version?(version)
        version.to_i > Helpers::NPM_V11
      end
      private_class_method :incompatible_version?

      sig { returns(T::Array[Dependabot::Version]) }
      def self.compatible_supported_versions
        NpmPackageManager::SUPPORTED_VERSIONS.reject { |version| incompatible_version?(version.to_s) }
      end
      private_class_method :compatible_supported_versions

      sig { returns(T.noreturn) }
      def self.raise_unsupported!
        raise ToolFeatureNotSupported.new(
          tool_name: NpmPackageManager::NAME,
          tool_type: "package manager",
          feature: FEATURE
        )
      end
      private_class_method :raise_unsupported!
    end
  end
end
