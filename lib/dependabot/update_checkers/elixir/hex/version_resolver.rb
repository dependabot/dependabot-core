# frozen_string_literal: true

require "excon"

require "dependabot/utils/elixir/version"
require "dependabot/update_checkers/elixir/hex"
require "dependabot/shared_helpers"
require "dependabot/errors"

module Dependabot
  module UpdateCheckers
    module Elixir
      class Hex
        class VersionResolver
          def initialize(dependency:, dependency_files:, credentials:)
            @dependency = dependency
            @dependency_files = dependency_files
            @credentials = credentials
          end

          def latest_resolvable_version
            @latest_resolvable_version ||=
              fetch_latest_resolvable_version
          end

          private

          attr_reader :dependency, :dependency_files, :credentials

          def fetch_latest_resolvable_version
            latest_resolvable_version =
              SharedHelpers.in_a_temporary_directory do
                write_temporary_dependency_files
                FileUtils.cp(
                  elixir_helper_check_update_path,
                  "check_update.exs"
                )

                SharedHelpers.run_helper_subprocess(
                  env: mix_env,
                  command: "mix run #{elixir_helper_path}",
                  function: "get_latest_resolvable_version",
                  args: [Dir.pwd, dependency.name]
                )
              end

            return if latest_resolvable_version.nil?
            if latest_resolvable_version.match?(/^[0-9a-f]{40}$/)
              return latest_resolvable_version
            end
            version_class.new(latest_resolvable_version)
          rescue SharedHelpers::HelperSubprocessFailed => error
            handle_hex_errors(error)
          end

          def handle_hex_errors(error)
            raise error unless error.message.start_with?("Invalid requirement")
            raise Dependabot::DependencyFileNotResolvable, error.message
          end

          def write_temporary_dependency_files
            dependency_files.each do |file|
              path = file.name
              FileUtils.mkdir_p(Pathname.new(path).dirname)
              File.write(path, file.content)
            end
          end

          def version_class
            Utils::Elixir::Version
          end

          def mix_env
            {
              "MIX_EXS" => File.join(project_root, "helpers/elixir/mix.exs"),
              "MIX_LOCK" => File.join(project_root, "helpers/elixir/mix.lock"),
              "MIX_DEPS" => File.join(project_root, "helpers/elixir/deps"),
              "MIX_QUIET" => "1"
            }
          end

          def elixir_helper_path
            File.join(project_root, "helpers/elixir/bin/run.exs")
          end

          def elixir_helper_check_update_path
            File.join(project_root, "helpers/elixir/bin/check_update.exs")
          end

          def project_root
            File.join(File.dirname(__FILE__), "../../../../..")
          end
        end
      end
    end
  end
end
