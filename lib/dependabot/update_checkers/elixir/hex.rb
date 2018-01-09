# frozen_string_literal: true

require "excon"
require "dependabot/update_checkers/base"
require "dependabot/shared_helpers"

require "json"

module Dependabot
  module UpdateCheckers
    module Elixir
      class Hex < Dependabot::UpdateCheckers::Base

        def latest_version
          return latest_resolvable_version unless hex_package

          versions =
            hex_package["releases"].map do |release|
              begin
                Gem::Version.new(release["version"])
              rescue ArgumentError
                nil
              end
            end.compact

            versions.reject(&:prerelease?).sort.last
        end

        def latest_resolvable_version
          @latest_resolvable_version ||= fetch_latest_resolvable_version
        end

        def updated_requirements
        end

        private

        def fetch_latest_resolvable_version
          latest_resolvable_version =
            SharedHelpers.in_a_temporary_directory do |dir|
              File.write("mix.exs", mixfile.content)
              File.write("mix.lock", lockfile.content)
              FileUtils.cp(
                elixir_helper_load_deps_path,
                File.join(dir, "check_update.exs")
              )

              SharedHelpers.run_helper_subprocess(
                env: {
                  "MIX_EXS" => elixir_helper_mix_exs_path,
                  "MIX_LOCK" => elixir_helper_mix_lock_path,
                  "MIX_DEPS" => elixir_helper_mix_deps_path,
                  "MIX_QUIET" => "1"
                },
                command: "mix run #{elixir_helper_path}",
                function: "get_latest_resolvable_version",
                args: [dir, dependency.name]
              )
            end

            puts "latest resolvable: #{latest_resolvable_version}"

          if latest_resolvable_version.nil?
            nil
          else
            Gem::Version.new(latest_resolvable_version)
          end
        #rescue SharedHelpers::HelperSubprocessFailed
          # TODO: We shouldn't be suppressing these errors but they're caused
          # by memory issues that we don't currently have a solution to.
         # nil
        end

        def elixir_helper_mix_exs_path
          project_root = File.join(File.dirname(__FILE__), "../../../..")
          File.join(project_root, "helpers/elixir/mix.exs")
        end

        def elixir_helper_mix_deps_path
          project_root = File.join(File.dirname(__FILE__), "../../../..")
          File.join(project_root, "helpers/elixir/deps")
        end

        def elixir_helper_mix_lock_path
          project_root = File.join(File.dirname(__FILE__), "../../../..")
          File.join(project_root, "helpers/elixir/mix.lock")
        end

        def elixir_helper_path
          project_root = File.join(File.dirname(__FILE__), "../../../..")
          File.join(project_root, "helpers/elixir/bin/run.exs")
        end

        def elixir_helper_load_deps_path
          project_root = File.join(File.dirname(__FILE__), "../../../..")
          File.join(project_root, "helpers/elixir/bin/check_update.exs")
        end

        def mixfile
          mixfile = dependency_files.find { |f| f.name == "mix.exs" }
          raise "No mix.exs!" unless mixfile
          mixfile
        end

        def lockfile
          lockfile = dependency_files.find { |f| f.name == "mix.lock" }
          raise "No mix.lock!" unless lockfile
          lockfile
        end

        def hex_package
          return @hex_package unless @hex_package.nil?

          response = Excon.get(
            dependency_url,
            idempotent: true,
            middlewares: SharedHelpers.excon_middleware
          )

          return nil unless response.status == 200

          @hex_package = JSON.parse(response.body)
        end

        def dependency_url
          "https://hex.pm/api/packages/#{dependency.name}"
        end
      end
    end
  end
end
