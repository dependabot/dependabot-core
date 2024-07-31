# typed: true
# frozen_string_literal: true

require "sorbet-runtime"

# This module extracts all helpers required to perform additional update job
# error recording and logging for various updates since they are shared
# between a few operations.
module Dependabot
  class Updater
    module UpdateHelpers
      extend T::Sig
      extend T::Helpers

      abstract!

      sig { returns(Dependabot::Service) }
      attr_reader :service

      # Logs a deprecation warning for a package manager version that is deprecated but the job will still succeed.
      #
      # @param package_manager [String] the name of the package manager
      # @param deprecated_version [String] the deprecated version of the package manager
      # @param supported_versions [Array<String>] the versions of the package manager that are still supported
      #
      # @example
      #   record_deprecation_warning_for_package_manager(
      #     package_manager: "bundler",
      #     deprecated_version: "1.17.3",
      #     supported_versions: ["2.x", "3.x"]
      #   )
      sig do
        params(
          package_manager: String,
          deprecated_version: String,
          supported_versions: T::Array[String]
        ).void
      end
      def record_deprecation_warning_for_package_manager(
        package_manager:,
        deprecated_version:,
        supported_versions:
      )
        Dependabot.logger.warn(
          "#{package_manager} version #{deprecated_version} is deprecated but the job will succeed. " \
          "Supported versions are: #{supported_versions.join(', ')}. Future updates are not guaranteed."
        )

        service.record_update_job_error(
          error_type: "#{package_manager}_deprecation_warning",
          error_details: {
            message: "#{package_manager} version #{deprecated_version} is deprecated.",
            "supported-versions": supported_versions
          }
        )
      end

      # Logs a deprecation error for a package manager version that is no longer supported, causing the job to fail.
      #
      # @param package_manager [String] the name of the package manager
      # @param deprecated_version [String] the deprecated version of the package manager
      # @param supported_versions [Array<String>] the versions of the package manager that are still supported
      #
      # @example
      #   record_deprecation_error_for_package_manager(
      #     package_manager: "bundler",
      #     deprecated_version: "1.17.3",
      #     supported_versions: ["2.x", "3.x"]
      #   )
      sig do
        params(
          package_manager: String,
          deprecated_version: String,
          supported_versions: T::Array[String]
        ).void
      end
      def record_deprecation_error_for_package_manager(
        package_manager:,
        deprecated_version:,
        supported_versions:
      )
        Dependabot.logger.error(
          "#{package_manager} version #{deprecated_version} is no longer supported. " \
          "Supported versions are: #{supported_versions.join(', ')}. The job will fail."
        )

        service.record_update_job_error(
          error_type: "#{package_manager}_deprecation_error",
          error_details: {
            message: "#{package_manager} version #{deprecated_version} is no longer supported.",
            "supported-versions": supported_versions
          }
        )
      end
    end
  end
end
