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

      # Logs a deprecation warning for a eco system version that is deprecated but the job will still succeed.
      #
      # @param eco_system [String] the name of the eco system
      # @param deprecated_version [String] the deprecated version of the eco system
      # @param supported_versions [Array<String>] the versions of the eco system that are still supported
      #
      # @example
      #   record_deprecation_warning_for_eco_system(
      #     eco_system: "bundler",
      #     deprecated_version: "v1",
      #     supported_versions: ["v2"]
      #   )
      sig do
        params(
          eco_system: String,
          deprecated_version: String,
          supported_versions: T.nilable(T::Array[String])
        ).void
      end
      def record_deprecation_warning_for_eco_system(
        eco_system:,
        deprecated_version:,
        supported_versions:
      )
        message = "#{eco_system} version #{deprecated_version} is deprecated but the job will succeed. " \

        message += "Supported versions are: #{supported_versions.join(', ')}." if supported_versions&.any?

        Dependabot.logger.warn(message)

        service.record_update_job_error(
          error_type: "#{eco_system}_deprecation_warning",
          error_details: {
            message: message,
            "deprecated-version": deprecated_version,
            "supported-versions": supported_versions
          }
        )
      end

      # Logs a deprecation error for a eco system version that is no longer supported, causing the job to fail.
      #
      # @param eco_system [String] the name of the eco system
      # @param deprecated_version [String] the deprecated version of the eco system
      # @param supported_versions [Array<String>] the versions of the eco system that are still supported
      #
      # @example
      #   record_deprecation_error_for_eco_system(
      #     eco_system: "bundler",
      #     deprecated_version: "v1",
      #     supported_versions: ["v2"]
      #   )
      sig do
        params(
          eco_system: String,
          not_supported_version: String,
          supported_versions: T.nilable(T::Array[String])
        ).void
      end
      def record_deprecation_error_for_eco_system(
        eco_system:,
        not_supported_version:,
        supported_versions:
      )
        message = "#{eco_system} version #{not_supported_version} is no longer supported.\n"

        message += "Supported versions are: #{supported_versions.join(', ')}." if supported_versions&.any?

        Dependabot.logger.error(message)

        service.record_update_job_error(
          error_type: "#{eco_system}_deprecation_error",
          error_details: {
            message: message,
            "not-supported-version": not_supported_version,
            "supported-versions": supported_versions
          }
        )
      end
    end
  end
end
