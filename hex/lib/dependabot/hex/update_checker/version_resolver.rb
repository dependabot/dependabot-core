# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

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
        RESOLUTION_FAILURE_PREFIX = "** (Mix) Hex dependency resolution failed"
        MAX_RESOLUTION_EXPLANATION_LENGTH = 4_000
        AMBIGUOUS_PACKAGE_ACCESS =
          "This could be because the package does not exist, it was spelled incorrectly " \
          "or you don't have permissions to it"
        ACCESS_EXPLANATION = "It may not exist, may be misspelled, or access may be unavailable."
        EXPLICIT_AUTHENTICATION_ERRORS = [
          "No authenticated user found. Run `mix hex.user auth` to authenticate",
          "Authentication failed (401)",
          "Forbidden (403)"
        ].freeze
        TIMEOUT_ERRORS = [
          ":timeout",
          "Request failed (:timeout)"
        ].freeze
        CONNECTION_ERRORS = %w(:closed :econnrefused :econnreset :ehostunreach :enetunreach :nxdomain).freeze
        HTTP_ERROR = /\A(?:HTTP status code: 5\d\d|Request failed \(5\d\d\))\z/
        QUALIFIED_FETCH_ERROR = Regexp.new(
          "\\AFailed to fetch record for " \
          "(?<source>[A-Za-z0-9_.:-]+)/(?<package>[A-Za-z0-9_.-]+) " \
          "from registry(?: \\(using cache instead\\))?\\z"
        )
        FETCH_ERROR =
          /\AFailed to fetch record for (?<package>[A-Za-z0-9_.-]+) from registry(?: \(using cache instead\))?\z/

        class ResolutionSubprocessFailed < SharedHelpers::HelperSubprocessFailed
          extend T::Sig

          sig { returns(String) }
          attr_reader :stdout

          sig { params(stdout: String, stderr: String, error_context: SharedHelpers::ErrorContext).void }
          def initialize(stdout:, stderr:, error_context:)
            @stdout = stdout
            super(message: stderr, error_context: error_context)
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
          handle_hex_errors(e)
        end

        sig { returns(String) }
        def resolve
          SharedHelpers.in_a_temporary_directory do
            write_temporary_dependency_files

            SharedHelpers.with_git_configured(credentials: credentials) do
              CredentialHelpers.configure(credentials: credentials, env: mix_env)
              run_elixir_update_checker
            end
          end
        end

        sig { returns(String) }
        def run_elixir_update_checker
          command = mix_run_command(elixir_helper_check_update_path, dependency.name)
          stdout, stderr, process, time_taken = CommandHelpers.capture3_with_timeout(
            [mix_env, *command_arguments(command)],
            timeout: RESOLUTION_TIMEOUT
          )
          stdout ||= ""
          stderr ||= ""

          unless process&.success?
            fingerprint = "mix run check_update.exs #{dependency.name}"
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

          File.read(RESULT_FILE)
        end

        sig do
          params(error: Dependabot::SharedHelpers::HelperSubprocessFailed)
            .returns(T.nilable(T.any(Dependabot::Version, String)))
        end
        def handle_hex_errors(error)
          source = CredentialHelpers.authentication_source(error)
          raise Dependabot::PrivateSourceAuthenticationFailure, source if source

          lines = error.message.lines.map(&:strip)
          qualified_fetch = lines.filter_map { |line| line.match(QUALIFIED_FETCH_ERROR) }.first

          handle_private_source_error(lines, qualified_fetch) if qualified_fetch
          handle_ambiguous_access_error(lines, qualified_fetch)

          raise error if source_less_network_failure?(lines)

          # Ignore dependencies which don't resolve due to mis-matching
          # environment specifications.
          # TODO: Update the environment specifications instead
          return if lines.any? { |line| line.include?("Dependencies have diverged") }

          handle_project_error(error, lines)

          raise error
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

        sig { returns(T::Hash[String, String]) }
        def mix_env
          {
            "HEX_HOME" => File.join(Dir.pwd, ".hex")
          }
        end

        sig { returns(String) }
        def elixir_helper_check_update_path
          File.join(NativeHelpers.hex_helpers_dir, "lib/check_update.exs")
        end

        sig { params(lines: T::Array[String]).returns(T.nilable(String)) }
        def bad_response_diagnostic(lines)
          lines.find do |line|
            CONNECTION_ERRORS.include?(line) || line.match?(HTTP_ERROR)
          end
        end

        sig { params(lines: T::Array[String]).returns(T::Boolean) }
        def source_less_network_failure?(lines)
          return true if lines.any? { |line| line.match?(FETCH_ERROR) }

          lines.include?("Failed to exchange API key for OAuth token")
        end

        sig { params(fetch: T.nilable(MatchData)).returns(String) }
        def ambiguous_access_message(fetch)
          return "Hex could not access the requested package. #{ACCESS_EXPLANATION}" unless fetch

          package = fetch[:package]
          source = fetch.names.include?("source") ? fetch[:source] : nil
          return "Hex could not access package \"#{package}\". #{ACCESS_EXPLANATION}" unless source

          "Hex could not access package \"#{package}\" from source \"#{private_source_name(source)}\". " \
            "#{ACCESS_EXPLANATION}"
        end

        sig { params(lines: T::Array[String], fetch: MatchData).void }
        def handle_private_source_error(lines, fetch)
          source = private_source_name(T.must(fetch[:source]))
          authentication_error = lines.intersect?(EXPLICIT_AUTHENTICATION_ERRORS)
          raise Dependabot::PrivateSourceAuthenticationFailure, source if authentication_error
          raise Dependabot::PrivateSourceTimedOut, source if lines.any? { |line| TIMEOUT_ERRORS.include?(line) }

          diagnostic = bad_response_diagnostic(lines)
          return unless diagnostic

          message = "Hex could not reach source \"#{source}\": #{diagnostic}"
          raise Dependabot::PrivateSourceBadResponse.new(source, message)
        end

        sig { params(lines: T::Array[String], qualified_fetch: T.nilable(MatchData)).void }
        def handle_ambiguous_access_error(lines, qualified_fetch)
          return unless lines.include?(AMBIGUOUS_PACKAGE_ACCESS)

          fetch = qualified_fetch || lines.filter_map { |line| line.match(FETCH_ERROR) }.first
          raise Dependabot::DependencyFileNotResolvable, ambiguous_access_message(fetch)
        end

        sig do
          params(
            error: Dependabot::SharedHelpers::HelperSubprocessFailed,
            lines: T::Array[String]
          ).void
        end
        def handle_project_error(error, lines)
          invalid_requirement = lines.any? do |line|
            line.start_with?("** (Version.InvalidRequirementError) invalid requirement:")
          end
          raise Dependabot::DependencyFileNotResolvable, error.message if invalid_requirement

          if lines.any? { |line| resolution_failure_line?(line) }
            explanation = resolution_explanation(error)
            message = "#{RESOLUTION_FAILURE_PREFIX.delete_prefix('** (Mix) ')}:\n#{explanation}" if explanation
            raise Dependabot::DependencyFileNotResolvable, message || error.message
          end

          unknown_dependency = /\A\*\* \(Mix\) Unknown dependency #{Regexp.escape(dependency.name)} for environment\b/
          return unless lines.any? { |line| line.match?(unknown_dependency) }

          raise Dependabot::DependencyFileNotResolvable, error.message
        end

        sig { params(line: String).returns(T::Boolean) }
        def resolution_failure_line?(line)
          line == RESOLUTION_FAILURE_PREFIX || line.start_with?("#{RESOLUTION_FAILURE_PREFIX}. ")
        end

        sig { params(error: Dependabot::SharedHelpers::HelperSubprocessFailed).returns(T.nilable(String)) }
        def resolution_explanation(error)
          return unless error.is_a?(ResolutionSubprocessFailed)

          lines =
            error
            .stdout
            .encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
            .gsub(%r{\e\[[0-?]*[ -/]*[@-~]}, "")
            .gsub(/[^\P{C}\n\t]/, "")
            .lines
            .map(&:rstrip)

          start = lines.index do |line|
            line.start_with?("Because ", "Note: active policy", "Active policy:", "Policy hid ")
          end
          return unless start

          candidate_lines = lines.drop(start)
          solver_end = candidate_lines.index { |line| line.include?("version solving failed") }
          solver_lines = solver_end ? candidate_lines.take(solver_end + 1) : []
          policy_lines = candidate_lines.drop(solver_end ? solver_end + 1 : 0).select do |line|
            policy_explanation_line?(line)
          end
          explanation = (solver_lines + policy_lines).join.strip
          return if explanation.empty?

          explanation.each_char.take(MAX_RESOLUTION_EXPLANATION_LENGTH).join
        end

        sig { params(line: String).returns(T::Boolean) }
        def policy_explanation_line?(line)
          return false if line.include?("HEX_POLICY") || line.include?("run without the policy") ||
                          line.include?("To install anyway")

          line.empty? ||
            line.start_with?(
              "Note: active policy",
              "Active policy:",
              "Effective cooldown:",
              "Policy hid ",
              "Versions filtered by cooldown:",
              "  "
            )
        end

        sig { params(source: String).returns(String) }
        def private_source_name(source)
          source.delete_prefix("hexpm:")
        end
      end
    end
  end
end
