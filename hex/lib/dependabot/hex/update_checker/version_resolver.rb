# frozen_string_literal: true

require "dependabot/hex/version"
require "dependabot/hex/update_checker"
require "dependabot/hex/native_helpers"
require "dependabot/shared_helpers"
require "dependabot/errors"

module Dependabot
  module Hex
    class UpdateChecker
      class VersionResolver
        def initialize(dependency:, credentials:,
                       original_dependency_files:, prepared_dependency_files:)
          @dependency = dependency
          @original_dependency_files = original_dependency_files
          @prepared_dependency_files = prepared_dependency_files
          @credentials = credentials
        end

        def latest_resolvable_version
          @latest_resolvable_version ||= fetch_latest_resolvable_version
        end

        private

        attr_reader :dependency, :credentials,
                    :original_dependency_files, :prepared_dependency_files

        def fetch_latest_resolvable_version
          latest_resolvable_version =
            SharedHelpers.in_a_temporary_directory do
              write_temporary_dependency_files
              FileUtils.cp(
                elixir_helper_check_update_path,
                "check_update.exs"
              )

              SharedHelpers.with_git_configured(credentials: credentials) do
                run_elixir_update_checker
              end
            end

          return if latest_resolvable_version.nil?
          if latest_resolvable_version.match?(/^[0-9a-f]{40}$/)
            return latest_resolvable_version
          end

          version_class.new(latest_resolvable_version)
        rescue SharedHelpers::HelperSubprocessFailed => error
          handle_hex_errors(error)
        end

        def run_elixir_update_checker
          SharedHelpers.run_helper_subprocess(
            env: mix_env,
            command: "mix run #{elixir_helper_path}",
            function: "get_latest_resolvable_version",
            args: [Dir.pwd,
                   dependency.name,
                   organization_credentials],
            popen_opts: { err: %i(child out) }
          )
        end

        def handle_hex_errors(error)
          if error.message.include?("No authenticated organization found")
            org = error.message.match(/found for ([a-z_]+)\./).captures.first
            raise Dependabot::PrivateSourceAuthenticationFailure, org
          end

          if error.message.include?("Failed to fetch record for")
            org_match = error.message.match(%r{for 'hexpm:([a-z_]+)/})
            org = org_match&.captures&.first
            raise Dependabot::PrivateSourceAuthenticationFailure, org if org
          end

          # TODO: This isn't pretty. It would be much nicer to catch the
          # warnings as part of the Elixir module.
          return error_result(error) if includes_result?(error)

          # Ignore dependencies which don't resolve due to mis-matching
          # environment specifications.
          # TODO: Update the environment specifications instead
          return if error.message.include?("Dependencies have diverged")

          check_original_requirements_resolvable
          raise error
        end

        def error_result(error)
          return false unless includes_result?(error)

          result_json = error.message&.split("\n")&.last
          result = JSON.parse(result_json)["result"]
          return version_class.new(result) if version_class.correct?(result)

          result
        end

        def includes_result?(error)
          result = error.message&.split("\n")&.last
          return false unless result

          JSON.parse(error.message&.split("\n")&.last)["result"]
          true
        rescue JSON::ParserError
          false
        end

        def check_original_requirements_resolvable
          SharedHelpers.in_a_temporary_directory do
            write_temporary_dependency_files(prepared: false)
            FileUtils.cp(
              elixir_helper_check_update_path,
              "check_update.exs"
            )

            SharedHelpers.with_git_configured(credentials: credentials) do
              run_elixir_update_checker
            end
          end

          true
        rescue SharedHelpers::HelperSubprocessFailed => error
          raise Dependabot::DependencyFileNotResolvable, error.message
        end

        def write_temporary_dependency_files(prepared: true)
          files = if prepared then prepared_dependency_files
                  else original_dependency_files
                  end

          files.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, file.content)
          end
        end

        def version_class
          Hex::Version
        end

        def mix_env
          {
            "MIX_EXS" => File.join(NativeHelpers.hex_helpers_dir, "mix.exs"),
            "MIX_LOCK" => File.join(NativeHelpers.hex_helpers_dir, "mix.lock"),
            "MIX_DEPS" => File.join(NativeHelpers.hex_helpers_dir, "deps"),
            "MIX_QUIET" => "1"
          }
        end

        def elixir_helper_path
          File.join(NativeHelpers.hex_helpers_dir, "lib/run.exs")
        end

        def elixir_helper_check_update_path
          File.join(NativeHelpers.hex_helpers_dir, "lib/check_update.exs")
        end

        def organization_credentials
          credentials.
            select { |cred| cred["type"] == "hex_organization" }.
            flat_map { |cred| [cred["organization"], cred["token"]] }
        end
      end
    end
  end
end
