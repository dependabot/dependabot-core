# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/error_report_context"
require "dependabot/shared_helpers"

module Dependabot
  module NpmAndYarn
    # Attaches debug-only `error-context` to failed npm, pnpm and Yarn commands. Only an allowlisted
    # subcommand is reported because command lines can contain credentials or private package names.
    module SubprocessErrorContext
      extend T::Sig

      SUBCOMMANDS = %w(add audit config dedupe exec info install list outdated remove up update upgrade view why).freeze

      # A whole semver version, so command output that merely starts with a version is never reported.
      VERSION_PATTERN = /\A\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?\z/

      sig { params(version: T.nilable(String)).returns(T::Boolean) }
      def self.valid_version?(version)
        !version.nil? && VERSION_PATTERN.match?(version)
      end

      sig do
        params(
          error: SharedHelpers::HelperSubprocessFailed,
          package_manager: String,
          command: String,
          version: T.nilable(String),
          registry: T.nilable(String)
        ).void
      end
      def self.attach(error, package_manager:, command:, version:, registry:)
        ErrorReportContext.attach(
          error,
          {
            command_name: command_name(package_manager, command),
            package_manager_version: valid_version?(version) ? version : nil,
            registry_host: registry && registry_host(registry)
          }
        )
      end

      sig { params(package_manager: String, command: String).returns(String) }
      def self.command_name(package_manager, command)
        subcommand = command.split.first
        SUBCOMMANDS.include?(subcommand) ? "#{package_manager} #{subcommand}" : package_manager
      end

      sig { params(registry: String).returns(T.nilable(String)) }
      def self.registry_host(registry)
        host = ErrorReportContext.host_for(registry)
        host == ErrorReportContext::REDACTED ? nil : host
      end
      private_class_method :command_name, :registry_host
    end
  end
end
