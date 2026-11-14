# typed: strict
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
      PROBE_TIMEOUT = 10

      sig { params(executable: String, env: T.nilable(T::Hash[String, String])).void }
      def initialize(executable:, env:)
        @executable = executable
        @env = env
        parts = executable.delete_prefix("corepack ").split("@", 2)
        @package_manager = T.let(parts.fetch(0), String)
        # A Corepack-pinned executable (e.g. "corepack npm@10") already carries the selected version, so
        # it never needs probing. Only a bare "npm"/"pnpm"/"yarn" executable leaves this nil.
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
            package_manager_version: @known_version || probed_version,
            host: ErrorReportContext.host_for(registry)
          }
        )
      end

      private

      sig { params(command: String).returns(String) }
      def command_name(command)
        action = COMMANDS.find { |name| command.match?(/\A\s*#{name}(?:\s|\z)/) }
        action ? "#{@package_manager} #{action}" : @package_manager
      end

      # Dependabot already resolves the configured registry from .npmrc/.yarnrc(.yml)/dependabot.yml
      # before running any command (see Helpers.merge_corepack_env), and writes it into these same env
      # keys for every package manager. Reading it back needs no subprocess.
      sig { returns(String) }
      def registry
        @env&.fetch(RegistryHelper::NPM_CONFIG_REGISTRY_ENV, nil) ||
          @env&.fetch(RegistryHelper::COREPACK_NPM_REGISTRY_ENV, nil) ||
          RegistryHelper::DEFAULT_NPM_REGISTRY
      end

      sig { returns(T.nilable(String)) }
      def probed_version
        output = probe("--version")
        return unless output

        version = output.lines.map(&:strip).reverse.find { |line| VERSION.match?(line) }
        Dependabot.logger.warn("Could not parse #{@package_manager} version for error context") unless version
        version
      end

      sig { params(command: String).returns(T.nilable(String)) }
      def probe(command)
        started_at = Time.now
        SharedHelpers.run_shell_command(
          "#{@executable} #{command}",
          fingerprint: "#{@package_manager} #{command}",
          env: @env,
          timeout: PROBE_TIMEOUT,
          # `timeout` above only resets after a period of silence, so a probe that keeps producing
          # output could otherwise run indefinitely. Enforce a wall-clock deadline alongside it.
          output_observer: lambda do |_output|
            next {} if Time.now - started_at < PROBE_TIMEOUT

            { gracefully_stop: true, reason: "Diagnostic probe exceeded its #{PROBE_TIMEOUT}s deadline" }
          end
        ).strip
      rescue SharedHelpers::HelperSubprocessFailed, SystemCallError, Timeout::Error => e
        Dependabot.logger.warn("Could not collect #{@package_manager} error context (#{e.class})")
        nil
      end
    end
  end
end
