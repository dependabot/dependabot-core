# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/error_report_context"
require "dependabot/npm_and_yarn/registry_helper"
require "dependabot/shared_helpers"

module Dependabot
  module NpmAndYarn
    class SubprocessErrorContext
      extend T::Sig

      # Only allowlisted operation names are reported; fingerprints and command arguments may contain secrets.
      PACKAGE_MANAGERS = %w(npm pnpm yarn).freeze
      COMMANDS = %w(add audit config dedupe dlx info install list outdated remove update up upgrade why).freeze
      VERSION = /\A\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?\z/

      sig { params(executable: String, registry: T.nilable(String)).void }
      def initialize(executable:, registry:)
        @registry = registry
        parts = executable.delete_prefix("corepack ").split("@", 2)
        @package_manager = T.let(parts.fetch(0), String)
        @known_version = T.let(parts[1], T.nilable(String))
      end

      sig { params(error: SharedHelpers::HelperSubprocessFailed, command: String).void }
      def attach(error, command)
        return unless PACKAGE_MANAGERS.include?(@package_manager)

        ErrorReportContext.attach(error, { command_name: command_name(command) })
        return if %w(-v --version).include?(command.strip)

        ErrorReportContext.attach(
          error,
          {
            package_manager_version: precise_known_version,
            host: ErrorReportContext.host_for(@registry || RegistryHelper::DEFAULT_NPM_REGISTRY)
          }
        )
      end

      private

      sig { params(command: String).returns(String) }
      def command_name(command)
        action = COMMANDS.find { |name| command.match?(/\A\s*#{name}(?:\s|\z)/) }
        action ? "#{@package_manager} #{action}" : @package_manager
      end

      # A cached-major selector does not identify an exact version.
      sig { returns(T.nilable(String)) }
      def precise_known_version
        @known_version if @known_version && VERSION.match?(@known_version)
      end
    end
  end
end
