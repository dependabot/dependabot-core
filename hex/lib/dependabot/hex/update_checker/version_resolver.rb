# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

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

        sig do
          params(
            dependency: Dependabot::Dependency,
            credentials: T::Array[Dependabot::Credential],
            original_dependency_files: T::Array[Dependabot::DependencyFile],
            prepared_dependency_files: T::Array[Dependabot::DependencyFile]
          ).void
        end
        def initialize(dependency:, credentials:,
                       original_dependency_files:, prepared_dependency_files:)
          @dependency = T.let(dependency, Dependabot::Dependency)
          @original_dependency_files = T.let(original_dependency_files, T::Array[Dependabot::DependencyFile])
          @prepared_dependency_files = T.let(prepared_dependency_files, T::Array[Dependabot::DependencyFile])
          @credentials = T.let(credentials, T::Array[Dependabot::Credential])
          @latest_resolvable_version = T.let(nil, T.nilable(T.any(Dependabot::Version, String, T::Boolean)))
        end

        sig { returns(T.nilable(T.any(Dependabot::Version, String, T::Boolean))) }
        def latest_resolvable_version
          @latest_resolvable_version ||= fetch_latest_resolvable_version
        end

        private

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :original_dependency_files

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :prepared_dependency_files

        sig { returns(T.nilable(T.any(Dependabot::Version, String, T::Boolean))) }
        def fetch_latest_resolvable_version
          latest_resolvable_version =
            SharedHelpers.in_a_temporary_directory do
              write_temporary_sanitized_dependency_files
              FileUtils.cp(elixir_helper_check_update_path, "check_update.exs")

              SharedHelpers.with_git_configured(credentials: credentials) do
                run_elixir_update_checker
              end
            end

          return if latest_resolvable_version.nil?
          return latest_resolvable_version if latest_resolvable_version.match?(/^[0-9a-f]{40}$/)

          version_class.new(latest_resolvable_version)
        rescue SharedHelpers::HelperSubprocessFailed => e
          handle_hex_errors(e)
        end

        sig { returns(String) }
        def run_elixir_update_checker
          SharedHelpers.run_helper_subprocess(
            env: mix_env,
            command: "mix run #{elixir_helper_path}",
            function: "get_latest_resolvable_version",
            args: [Dir.pwd, dependency.name, CredentialHelpers.hex_credentials(credentials)],
            stderr_to_stdout: true
          )
        end

        sig do
          params(error: Dependabot::SharedHelpers::HelperSubprocessFailed)
            .returns(T.nilable(T.any(Dependabot::Version, String, T::Boolean)))
        end
        def handle_hex_errors(error)
          if (match = error.message.match(/No authenticated organization found for (?<repo>[a-z_]+)\./))
            raise Dependabot::PrivateSourceAuthenticationFailure, match[:repo]
          end

          if (match = error.message.match(/Public key fingerprint mismatch for repo "(?<repo>[a-z_]+)"/))
            raise Dependabot::PrivateSourceAuthenticationFailure, match[:repo]
          end

          if (match = error.message.match(/Missing credentials for "(?<repo>[a-z_]+)"/))
            raise Dependabot::PrivateSourceAuthenticationFailure, match[:repo]
          end

          if (match = error.message.match(/Downloading public key for repo "(?<repo>[a-z_]+)"/))
            raise Dependabot::PrivateSourceAuthenticationFailure, match[:repo]
          end

          if (match = error.message.match(/Failed to fetch record for (?<repo>[a-z_]+)(?::(?<org>[a-z_]+))?/))
            name = match[:org] || match[:repo]
            raise Dependabot::PrivateSourceAuthenticationFailure, name
          end

          # TODO: Catch the warnings as part of the Elixir module. This happens
          # when elixir throws warnings from the manifest files that end up in
          # stdout and cause run_helper_subprocess to fail parsing the result as
          # JSON.
          return error_result(error) if includes_result?(error)

          # Ignore dependencies which don't resolve due to mis-matching
          # environment specifications.
          # TODO: Update the environment specifications instead
          return if error.message.include?("Dependencies have diverged")

          check_original_requirements_resolvable
          raise error
        end

        sig do
          params(error: Dependabot::SharedHelpers::HelperSubprocessFailed).returns(
            T.any(
              Dependabot::Version,
              String,
              T::Boolean
            )
          )
        end
        def error_result(error)
          return false unless includes_result?(error)

          result_json = error.message.split("\n").last
          result = JSON.parse(T.must(result_json))["result"]
          return version_class.new(result) if version_class.correct?(result)

          result
        end

        sig { params(error: Dependabot::SharedHelpers::HelperSubprocessFailed).returns(T::Boolean) }
        def includes_result?(error)
          result = error.message.split("\n").last
          return false unless result

          JSON.parse(result).key?("result")
        rescue JSON::ParserError
          false
        end

        sig { returns(T.any(T::Boolean, Dependabot::Version, String)) }
        def check_original_requirements_resolvable
          SharedHelpers.in_a_temporary_directory do
            write_temporary_sanitized_dependency_files(prepared: false)
            FileUtils.cp(
              elixir_helper_check_update_path,
              "check_update.exs"
            )

            SharedHelpers.with_git_configured(credentials: credentials) do
              run_elixir_update_checker
            end
          end

          true
        rescue SharedHelpers::HelperSubprocessFailed => e
          # TODO: Catch the warnings as part of the Elixir module. This happens
          # when elixir throws warnings from the manifest files that end up in
          # stdout and cause run_helper_subprocess to fail parsing the result as
          # JSON.
          return error_result(e) if includes_result?(e)

          raise Dependabot::DependencyFileNotResolvable, e.message
        end

        sig { params(prepared: T::Boolean).void }
        def write_temporary_sanitized_dependency_files(prepared: true)
          files = if prepared then prepared_dependency_files
                  else
                    original_dependency_files
                  end

          files.each do |file|
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
            "MIX_EXS" => File.join(NativeHelpers.hex_helpers_dir, "mix.exs"),
            "MIX_QUIET" => "1"
          }
        end

        sig { returns(String) }
        def elixir_helper_path
          File.join(NativeHelpers.hex_helpers_dir, "lib/run.exs")
        end

        sig { returns(String) }
        def elixir_helper_check_update_path
          File.join(NativeHelpers.hex_helpers_dir, "lib/check_update.exs")
        end
      end
    end
  end
end
