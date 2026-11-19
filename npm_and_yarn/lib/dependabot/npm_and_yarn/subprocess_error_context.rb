# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/error_report_context"
require "dependabot/shared_helpers"
require "dependabot/npm_and_yarn/subprocess_diagnostic_probe"

module Dependabot
  module NpmAndYarn
    class SubprocessErrorContext
      extend T::Sig

      # Only allowlisted operation names are reported; fingerprints and command arguments may contain secrets.
      PACKAGE_MANAGERS = %w(npm pnpm yarn).freeze
      COMMANDS = %w(add audit config dedupe dlx info install list outdated remove update up upgrade why).freeze
      VERSION = SubprocessDiagnosticProbe::VERSION

      sig do
        params(executable: String, registry_hosts: T::Array[String], env: T.nilable(T::Hash[String, String])).void
      end
      def initialize(executable:, registry_hosts:, env: nil)
        @executable = executable
        @env = env
        @registry_hosts = registry_hosts
        parts = executable.delete_prefix("corepack ").split("@", 2)
        @package_manager = T.let(parts.fetch(0), String)
        @selected_version = T.let(parts[1], T.nilable(String))
      end

      sig { params(error: SharedHelpers::HelperSubprocessFailed, command: String).void }
      def attach(error, command)
        return unless PACKAGE_MANAGERS.include?(@package_manager)

        ErrorReportContext.attach(error, { command_name: command_name(command) })
        return if %w(-v --version).include?(command.strip)

        ErrorReportContext.attach(
          error,
          {
            selected_package_manager_version: precise_selected_version,
            configured_registry_hosts: @registry_hosts
          }
        )
        ErrorReportContext.attach(error, SubprocessDiagnosticProbe.new(executable: @executable, env: @env).context)
      end

      private

      sig { params(command: String).returns(String) }
      def command_name(command)
        action = COMMANDS.find { |name| command.match?(/\A\s*#{name}(?:\s|\z)/) }
        action ? "#{@package_manager} #{action}" : @package_manager
      end

      # A cached-major selector does not identify an exact version.
      sig { returns(T.nilable(String)) }
      def precise_selected_version
        @selected_version if @selected_version && VERSION.match?(@selected_version)
      end
    end
  end
end
