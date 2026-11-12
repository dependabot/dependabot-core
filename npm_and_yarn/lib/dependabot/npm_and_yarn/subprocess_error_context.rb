# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/error_report_context"
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
        @package_manager = T.let(executable.delete_prefix("corepack ").split("@").first.to_s, String)
      end

      sig { params(error: SharedHelpers::HelperSubprocessFailed, command: String).void }
      def attach(error, command)
        return unless PACKAGE_MANAGERS.include?(@package_manager)

        ErrorReportContext.attach(error, { command_name: command_name(command) })
        return if %w(-v --version).include?(command.strip)

        version = package_manager_version
        registry = registry_url(version)
        ErrorReportContext.attach(
          error,
          {
            package_manager_version: version,
            host: registry && ErrorReportContext.host_for(registry)
          }
        )
      end

      private

      sig { params(command: String).returns(String) }
      def command_name(command)
        action = COMMANDS.find { |name| command.match?(/\A\s*#{name}(?:\s|\z)/) }
        action ? "#{@package_manager} #{action}" : @package_manager
      end

      sig { returns(T.nilable(String)) }
      def package_manager_version
        output = probe("--version")
        return unless output

        version = output.lines.map(&:strip).reverse.find { |line| VERSION.match?(line) }
        Dependabot.logger.warn("Could not parse #{@package_manager} version for error context") unless version
        version
      end

      sig { params(version: T.nilable(String)).returns(T.nilable(String)) }
      def registry_url(version)
        return if @package_manager == "yarn" && version.nil?

        key = @package_manager == "yarn" && !T.must(version).start_with?("1.") ? "npmRegistryServer" : "registry"
        output = probe("config get #{key}")
        return unless output

        registry = output.lines.map(&:strip).find { |line| line.start_with?("https://", "http://") }
        Dependabot.logger.warn("Could not parse #{@package_manager} registry for error context") unless registry
        registry
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
