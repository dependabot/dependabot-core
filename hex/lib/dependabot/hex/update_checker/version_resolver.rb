# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "tmpdir"

require "dependabot/command_helpers"
require "dependabot/hex/version"
require "dependabot/hex/update_checker"
require "dependabot/hex/credential_helpers"
require "dependabot/hex/native_helpers"
require "dependabot/hex/file_updater/mixfile_sanitizer"
require "dependabot/shared_helpers"
require "dependabot/errors"

module Dependabot
  module Hex
    class UpdateChecker
      class VersionResolver
        extend T::Sig

        RESULT_FILE = ".dependabot-result"
        RESOLUTION_TIMEOUT = 30
        GIT_FETCH_TIMEOUT = 120
        RESOLUTION_DIVERGENCE_HEADER = "Dependencies have diverged:"
        RESOLUTION_DIVERGENCE_TRAILER = "** (Mix) Can't continue due to errors on dependencies"
        RESOLUTION_FAILURE_PREFIX = "** (Mix) Hex dependency resolution failed"
        RESOLUTION_FAILURE_MESSAGE = "Hex dependency resolution failed"
        MAX_RESOLUTION_EXPLANATION_LENGTH = 4_000
        SOLVER_EXPLANATION_LINE =
          /\A(?:\(\d+\)\s+|\s+)?(?:Because |And because |So, because |This, )/
        MALFORMED_REQUIREMENT =
          %r{
            \A\*\*[ ]\(Mix\)[ ]Required[ ]version[ ].+[ ]for[ ]package[ ].+[ ]is[ ]incorrectly[ ]specified
            [ ]\(from:[ ](?:[^/\r\n]+/)*mix\.exs\)\z
          }x

        class ResolutionSubprocessFailed < SharedHelpers::HelperSubprocessFailed
          extend T::Sig

          sig { returns(String) }
          attr_reader :stdout

          sig do
            params(
              stdout: String,
              stderr: String,
              error_context: SharedHelpers::ErrorContext,
              error_class: T.nilable(String),
              trace: T.nilable(T::Array[String])
            ).void
          end
          def initialize(stdout:, stderr:, error_context:, error_class: nil, trace: nil)
            @stdout = stdout
            super(message: stderr, error_context: error_context, error_class: error_class, trace: trace)
          end
        end

        sig do
          params(
            dependency: Dependabot::Dependency,
            credentials: T::Array[Dependabot::Credential],
            prepared_dependency_files: T::Array[Dependabot::DependencyFile]
          ).void
        end
        def initialize(
          dependency:,
          credentials:,
          prepared_dependency_files:
        )
          @dependency = dependency
          @prepared_dependency_files = prepared_dependency_files
          @credentials = credentials
          @latest_resolvable_version = T.let(nil, T.nilable(T.any(Dependabot::Version, String)))
        end

        sig { returns(T.nilable(T.any(Dependabot::Version, String))) }
        def latest_resolvable_version
          @latest_resolvable_version ||= fetch_latest_resolvable_version
        end

        private

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :prepared_dependency_files

        sig { returns(T.nilable(T.any(Dependabot::Version, String))) }
        def fetch_latest_resolvable_version
          latest_resolvable_version = resolve

          return if latest_resolvable_version.nil?
          return latest_resolvable_version if latest_resolvable_version.match?(/^[0-9a-f]{40}$/)

          version_class.new(latest_resolvable_version)
        rescue SharedHelpers::HelperSubprocessFailed => e
          sanitized_error = sanitize_subprocess_error(e)
          error = handle_hex_errors(sanitized_error)
          return if error.nil?

          CredentialHelpers.raise_translated_error(original_error: e, error: error)
        end

        sig do
          params(error: SharedHelpers::HelperSubprocessFailed)
            .returns(SharedHelpers::HelperSubprocessFailed)
        end
        def sanitize_subprocess_error(error)
          sanitized_error = CredentialHelpers.sanitize_error(error: error, credentials: credentials)
          return sanitized_error unless error.is_a?(ResolutionSubprocessFailed)

          sanitized_stdout = sanitize_stdout(error.stdout)
          return error if sanitized_error.equal?(error) && sanitized_stdout == error.stdout

          ResolutionSubprocessFailed.new(
            stdout: sanitized_stdout,
            stderr: sanitized_error.message,
            error_context: sanitized_error.error_context,
            error_class: sanitized_error.error_class,
            trace: sanitized_error.trace
          )
        end

        sig { params(stdout: String).returns(String) }
        def sanitize_stdout(stdout)
          stdout_error = SharedHelpers::HelperSubprocessFailed.new(message: stdout, error_context: {})
          CredentialHelpers.sanitize_error(error: stdout_error, credentials: credentials).message
        end

        sig { returns(T.nilable(String)) }
        def resolve
          Dir.mktmpdir("dependabot-hex-home") do |hex_home|
            SharedHelpers.in_a_temporary_directory do
              write_temporary_dependency_files

              env = mix_env(hex_home)
              SharedHelpers.with_git_configured(credentials: credentials) do
                CredentialHelpers.configure(credentials: credentials, env: env)
                fetch_git_dependencies(env)
                run_elixir_update_checker(env)
              end
            end
          end
        end

        sig { params(env: T::Hash[String, String]).void }
        def fetch_git_dependencies(env)
          run_resolution_command(
            mix_run_command(elixir_helper_fetch_git_dependencies_path, dependency.name),
            fingerprint: "mix run fetch_git_dependencies.exs <dependency_name>",
            env: env,
            timeout: GIT_FETCH_TIMEOUT
          )
        end

        sig { params(env: T::Hash[String, String]).returns(T.nilable(String)) }
        def run_elixir_update_checker(env)
          command = mix_run_command(elixir_helper_check_update_path, dependency.name)
          run_resolution_command(
            command,
            fingerprint: "mix run check_update.exs <dependency_name>",
            env: env,
            timeout: RESOLUTION_TIMEOUT
          )
          File.read(RESULT_FILE)
        rescue SharedHelpers::HelperSubprocessFailed => e
          return if confirmed_resolution_divergence?(e)

          raise
        end

        sig do
          params(
            command: T::Array[String],
            fingerprint: String,
            env: T::Hash[String, String],
            timeout: Integer
          ).void
        end
        def run_resolution_command(command, fingerprint:, env:, timeout:)
          stdout, stderr, process, time_taken = CommandHelpers.capture3_with_timeout(
            [env, *command_arguments(command)],
            timeout: timeout
          )
          stdout ||= ""
          stderr ||= ""

          return if process&.success?

          error_context = {
            command: fingerprint,
            fingerprint: fingerprint,
            time_taken: time_taken,
            process_exit_value: process.to_s,
            stderr_output: stderr
          }

          SharedHelpers.check_out_of_disk_memory_error(stderr, error_context)
          raise ResolutionSubprocessFailed.new(stdout: stdout, stderr: stderr, error_context: error_context)
        end

        sig do
          params(error: Dependabot::SharedHelpers::HelperSubprocessFailed)
            .returns(T.nilable(StandardError))
        end
        def handle_hex_errors(error)
          source = CredentialHelpers.authentication_source(error.message)
          if source.nil? && error.is_a?(ResolutionSubprocessFailed)
            source = CredentialHelpers.authentication_source(error.stdout)
          end
          return Dependabot::PrivateSourceAuthenticationFailure.new(source) if source

          handle_project_error(error) || error
        end

        sig { params(error: SharedHelpers::HelperSubprocessFailed).returns(T::Boolean) }
        def confirmed_resolution_divergence?(error)
          output = error.message
          output = "#{error.stdout}\n#{output}" if error.is_a?(ResolutionSubprocessFailed)

          confirmed_resolution_divergence_output?(output)
        end

        sig { params(output: String).returns(T::Boolean) }
        def confirmed_resolution_divergence_output?(output)
          lines = output.lines.map(&:strip).reject(&:empty?)

          lines.include?(RESOLUTION_DIVERGENCE_HEADER) &&
            lines.last == RESOLUTION_DIVERGENCE_TRAILER
        end

        sig { params(script: String, args: String).returns(T::Array[String]) }
        def mix_run_command(script, *args)
          [
            "mix", "run", "--no-deps-check", "--no-start", "--no-compile",
            "--no-elixir-version-check", script, "--", *args
          ]
        end

        sig { params(command: T::Array[String]).returns(T::Array[CommandHelpers::EnvCmdItem]) }
        def command_arguments(command)
          executable = T.must(command.first)
          [[executable, executable], *command.drop(1)]
        end

        sig { void }
        def write_temporary_dependency_files
          prepared_dependency_files.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, sanitize_mixfile(T.must(file.content)))
          end
        end

        sig { params(content: String).returns(String) }
        def sanitize_mixfile(content)
          Hex::FileUpdater::MixfileSanitizer.new(
            mixfile_content: content
          ).sanitized_content
        end

        sig { returns(T.class_of(Dependabot::Version)) }
        def version_class
          dependency.version_class
        end

        sig { params(hex_home: String).returns(T::Hash[String, String]) }
        def mix_env(hex_home)
          {
            "HEX_HOME" => hex_home,
            "MIX_EXS" => "mix.exs"
          }
        end

        sig { returns(String) }
        def elixir_helper_check_update_path
          File.join(NativeHelpers.hex_helpers_dir, "lib/check_update.exs")
        end

        sig { returns(String) }
        def elixir_helper_fetch_git_dependencies_path
          File.join(NativeHelpers.hex_helpers_dir, "lib/fetch_git_dependencies.exs")
        end

        sig do
          params(error: Dependabot::SharedHelpers::HelperSubprocessFailed)
            .returns(T.nilable(StandardError))
        end
        def handle_project_error(error)
          lines = error.message.lines.map(&:strip)
          invalid_requirement = lines.find do |line|
            line.start_with?("** (Version.InvalidRequirementError) invalid requirement:")
          end
          return Dependabot::DependencyFileNotResolvable.new(invalid_requirement) if invalid_requirement

          malformed_requirement = lines.find { |line| line.match?(MALFORMED_REQUIREMENT) }
          return Dependabot::DependencyFileNotResolvable.new(malformed_requirement) if malformed_requirement

          raise_dependency_resolution_error(error, lines)

          unknown_dependency = /\A\*\* \(Mix\) Unknown dependency #{Regexp.escape(dependency.name)} for environment\b/
          unknown_dependency_diagnostic = lines.find { |line| line.match?(unknown_dependency) }
          return unless unknown_dependency_diagnostic

          Dependabot::DependencyFileNotResolvable.new(unknown_dependency_diagnostic)
        end

        sig do
          params(
            error: Dependabot::SharedHelpers::HelperSubprocessFailed,
            lines: T::Array[String]
          ).void
        end
        def raise_dependency_resolution_error(error, lines)
          diagnostic_lines = lines.reject(&:empty?)
          return if diagnostic_lines.empty?
          return unless diagnostic_lines.all? { |line| resolution_failure_line?(line) }

          explanation = resolution_explanation(error)
          message = explanation ? "#{RESOLUTION_FAILURE_MESSAGE}:\n#{explanation}" : RESOLUTION_FAILURE_MESSAGE
          raise Dependabot::DependencyFileNotResolvable.new(message), cause: nil
        end

        sig { params(line: String).returns(T::Boolean) }
        def resolution_failure_line?(line)
          line == RESOLUTION_FAILURE_PREFIX || line.start_with?("#{RESOLUTION_FAILURE_PREFIX}. ")
        end

        sig { params(error: Dependabot::SharedHelpers::HelperSubprocessFailed).returns(T.nilable(String)) }
        def resolution_explanation(error)
          return unless error.is_a?(ResolutionSubprocessFailed)

          normalized_stdout =
            error
            .stdout
            .encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
            .gsub(%r{\e\[[0-?]*[ -/]*[@-~]}, "")
            .gsub(/[^\P{C}\n\t]/, "")

          lines =
            sanitize_stdout(normalized_stdout)
            .lines
            .map(&:rstrip)

          explanation = resolution_explanation_lines(lines).join("\n").strip
          return if explanation.empty?

          explanation.each_char.take(MAX_RESOLUTION_EXPLANATION_LENGTH).join
        end

        sig { params(lines: T::Array[String]).returns(T::Array[String]) }
        def resolution_explanation_lines(lines)
          return [] if lines.any? { |line| policy_bypass_line?(line) }

          solver_end = lines.rindex { |line| line.include?("version solving failed") }
          return policy_explanation_lines(lines) unless solver_end

          solver_start = solver_explanation_start(lines, solver_end)
          return [] unless solver_start

          solver_lines = lines.drop(solver_start).take(solver_end - solver_start + 1)
          return [] unless solver_lines.all? { |line| solver_explanation_line?(line) }

          solver_lines + policy_explanation_lines(lines.drop(solver_end + 1))
        end

        sig { params(lines: T::Array[String], solver_end: Integer).returns(T.nilable(Integer)) }
        def solver_explanation_start(lines, solver_end)
          preceding_lines = lines.take(solver_end + 1)
          preamble = preceding_lines.rindex("Resolving Hex dependencies...")
          return preceding_lines.rindex { |line| solver_because_line?(line) } unless preamble

          solver_range = ((preamble + 1)..solver_end)
          numbered_start = solver_range.find { |index| numbered_solver_line?(lines.fetch(index)) }
          if numbered_start
            return numbered_start if solver_because_line?(lines.fetch(numbered_start))

            preceding_range = ((preamble + 1)...numbered_start)
            return preceding_range.reverse_each.find { |index| solver_because_line?(lines.fetch(index)) } ||
                   numbered_start
          end

          solver_range.reverse_each.find { |index| solver_because_line?(lines.fetch(index)) }
        end

        sig { params(lines: T::Array[String]).returns(T::Array[String]) }
        def policy_explanation_lines(lines)
          start = lines.index do |line|
            line.start_with?("Note: active policy", "Active policy:", "Policy hid ")
          end
          return [] unless start

          lines.drop(start).select { |line| policy_explanation_line?(line) }
        end

        sig { params(line: String).returns(T::Boolean) }
        def solver_explanation_line?(line)
          return false if policy_bypass_line?(line)

          line.empty? || line.match?(SOLVER_EXPLANATION_LINE)
        end

        sig { params(line: String).returns(T::Boolean) }
        def solver_because_line?(line)
          line.match?(/\A(?:\(\d+\)\s+|\s+)?Because /)
        end

        sig { params(line: String).returns(T::Boolean) }
        def numbered_solver_line?(line)
          line.match?(/\A\(\d+\)\s+/)
        end

        sig { params(line: String).returns(T::Boolean) }
        def policy_explanation_line?(line)
          return false if policy_bypass_line?(line)

          line.empty? ||
            line.start_with?(
              "Note: active policy",
              "Active policy:",
              "Effective cooldown:",
              "Policy hid ",
              "Versions filtered by cooldown:"
            )
        end

        sig { params(line: String).returns(T::Boolean) }
        def policy_bypass_line?(line)
          line.include?("HEX_POLICY") ||
            line.include?("run without the policy") ||
            line.include?("To install anyway")
        end
      end
    end
  end
end
