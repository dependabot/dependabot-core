# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "tmpdir"

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
        MALFORMED_REQUIREMENT =
          /\A\*\* \(Mix\) Required version .+ for package .+ is incorrectly specified \(from: mix\.exs\)\z/

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
          Dir.mktmpdir("dependabot-hex-home") do |hex_home|
            SharedHelpers.in_a_temporary_directory do
              write_temporary_dependency_files

              env = mix_env(hex_home)
              SharedHelpers.with_git_configured(credentials: credentials) do
                CredentialHelpers.configure(credentials: credentials, env: env)
                run_elixir_update_checker(env)
              end
            end
          end
        end

        sig { params(env: T::Hash[String, String]).returns(String) }
        def run_elixir_update_checker(env)
          SharedHelpers.run_shell_command(
            mix_run_command(elixir_helper_check_update_path, dependency.name),
            env: env,
            fingerprint: "mix run check_update.exs #{dependency.name}",
            timeout: RESOLUTION_TIMEOUT
          )
          File.read(RESULT_FILE)
        end

        sig do
          params(error: Dependabot::SharedHelpers::HelperSubprocessFailed)
            .returns(T.nilable(T.any(Dependabot::Version, String)))
        end
        def handle_hex_errors(error)
          lines = error.message.lines.map(&:strip)
          authentication = lines.filter_map do |line|
            line.match(
              /\A(?:\*\* \(Mix\) )?No authenticated organization found for (?<source>[A-Za-z0-9_.-]+)\.\z/
            ) || line.match(/\AMissing credentials for "(?<source>[A-Za-z0-9_.-]+)"\z/)
          end.first
          raise Dependabot::PrivateSourceAuthenticationFailure, authentication[:source] if authentication

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
            "MIX_QUIET" => "1"
          }
        end

        sig { returns(String) }
        def elixir_helper_check_update_path
          File.join(NativeHelpers.hex_helpers_dir, "lib/check_update.exs")
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

          if lines.any? { |line| line.match?(MALFORMED_REQUIREMENT) }
            raise Dependabot::DependencyFileNotResolvable, error.message
          end

          unknown_dependency = /\A\*\* \(Mix\) Unknown dependency #{Regexp.escape(dependency.name)} for environment\b/
          return unless lines.any? { |line| line.match?(unknown_dependency) }

          raise Dependabot::DependencyFileNotResolvable, error.message
        end
      end
    end
  end
end
