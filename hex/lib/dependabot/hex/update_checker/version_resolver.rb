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

        RESULT_FILE = ".dependabot-result"

        sig do
          params(
            dependency: Dependabot::Dependency,
            credentials: T::Array[Dependabot::Credential],
            original_dependency_files: T::Array[Dependabot::DependencyFile],
            prepared_dependency_files: T::Array[Dependabot::DependencyFile]
          ).void
        end
        def initialize(
          dependency:,
          credentials:,
          original_dependency_files:,
          prepared_dependency_files:
        )
          @dependency = dependency
          @original_dependency_files = original_dependency_files
          @prepared_dependency_files = prepared_dependency_files
          @credentials = credentials
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
              copy_elixir_helpers

              SharedHelpers.with_git_configured(credentials: credentials) do
                CredentialHelpers.configure(credentials: credentials, env: mix_env)
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
          SharedHelpers.run_shell_command(
            mix_run_command("check_update.exs", dependency.name),
            env: mix_env,
            fingerprint: "mix run check_update.exs #{dependency.name}"
          )
          File.read(RESULT_FILE)
        end

        sig do
          params(error: Dependabot::SharedHelpers::HelperSubprocessFailed)
            .returns(T.nilable(T.any(Dependabot::Version, String, T::Boolean)))
        end
        def handle_hex_errors(error)
          handle_new_private_organization_authentication_error(error.message)

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

          if (match = error.message.match(/Failed to decode public key for repo "(?<repo>[a-z_]+)"/))
            raise Dependabot::PrivateSourceAuthenticationFailure, match[:repo]
          end

          if (match = error.message.match(/Failed to fetch record for (?<repo>[a-z_]+)(?::(?<org>[a-z_]+))?/))
            name = match[:org] || match[:repo]
            raise Dependabot::PrivateSourceAuthenticationFailure, name
          end

          # Ignore dependencies which don't resolve due to mis-matching
          # environment specifications.
          # TODO: Update the environment specifications instead
          return if error.message.include?("Dependencies have diverged")

          check_original_requirements_resolvable
          raise error
        end

        sig { params(message: String).void }
        def handle_new_private_organization_authentication_error(message)
          return unless new_private_organization_authentication_error?(message)

          organization = private_organization
          raise Dependabot::PrivateSourceAuthenticationFailure, organization if organization
        end

        sig { params(message: String).returns(T::Boolean) }
        def new_private_organization_authentication_error?(message)
          message.include?("Failed to exchange API key for OAuth token") ||
            message.include?("No authenticated user found. Do you want to authenticate now?") ||
            message.include?("Failed to authenticate against organization repository")
        end

        sig { returns(T.nilable(String)) }
        def private_organization
          credential = credentials.find { |item| item["type"] == "hex_organization" }
          organization = credential&.fetch("organization", nil)
          return organization unless organization.to_s.empty?

          lockfile = original_dependency_files.find { |file| file.name == "mix.lock" }
          lockfile&.content&.match(
            /"#{Regexp.escape(dependency.name)}".*?"hexpm:(?<organization>[a-z_]+)"/m
          )&.named_captures&.fetch("organization", nil)
        end

        sig { returns(T.any(T::Boolean, Dependabot::Version, String)) }
        def check_original_requirements_resolvable
          SharedHelpers.in_a_temporary_directory do
            write_temporary_sanitized_dependency_files(prepared: false)
            copy_elixir_helpers

            SharedHelpers.with_git_configured(credentials: credentials) do
              CredentialHelpers.configure(credentials: credentials, env: mix_env)
              run_elixir_update_checker
            end
          end

          true
        rescue SharedHelpers::HelperSubprocessFailed => e
          raise Dependabot::DependencyFileNotResolvable, e.message
        end

        sig { void }
        def copy_elixir_helpers
          FileUtils.cp(CredentialHelpers.configure_credentials_path, "configure_credentials.exs")
          FileUtils.cp(elixir_helper_check_update_path, "check_update.exs")
        end

        sig { params(script: String, args: String).returns(T::Array[String]) }
        def mix_run_command(script, *args)
          [
            "mix", "run", "--no-deps-check", "--no-start", "--no-compile",
            "--no-elixir-version-check", script, "--", *args
          ]
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
            "HEX_HOME" => File.join(Dir.pwd, ".hex"),
            "MIX_QUIET" => "1"
          }
        end

        sig { returns(String) }
        def elixir_helper_check_update_path
          File.join(NativeHelpers.hex_helpers_dir, "lib/check_update.exs")
        end
      end
    end
  end
end
