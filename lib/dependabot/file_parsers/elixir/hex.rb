# frozen_string_literal: true
require "dependabot/dependency"
require "dependabot/file_parsers/base"
require "dependabot/file_fetchers/elixir/hex"
require "dependabot/shared_helpers"

module Dependabot
  module FileParsers
    module Elixir
      class Hex < Dependabot::FileParsers::Base
        def parse
          dependency_versions.map do |dep|
            Dependency.new(
              name: dep["name"],
              version: dep["version"],
              requirements: [{
                requirement: dep["requirement"],
                groups: [],
                source: nil,
                file: "mix.exs"
              }],
              package_manager: "hex",
            )
          end
        end

        private

        def dependency_versions
          SharedHelpers.in_a_temporary_directory do |dir|
            File.write(File.join(dir, "mix.exs"), mixfile.content)
            File.write(File.join(dir, "mix.lock"), lockfile.content)
            FileUtils.cp(elixir_helper_load_deps_path, File.join(dir, "load_deps.exs"))

            SharedHelpers.run_helper_subprocess(
              env: {
                "MIX_EXS" => elixir_helper_mix_exs_path,
                "MIX_LOCK" => elixir_helper_mix_lock_path,
                "MIX_DEPS" => elixir_helper_mix_deps_path,
                "MIX_QUIET" => "1",
              },
              command: "mix run #{elixir_helper_path}",
              function: "parse",
              args: [dir]
            )
          end
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
          File.join(project_root, "helpers/elixir/bin/load_deps.exs")
        end


        def required_files
          Dependabot::FileFetchers::Elixir::Hex.required_files
        end

        def check_required_files
          # TODO
          return
        end

        def mixfile
          @mixfile ||= get_original_file("mix.exs")
        end

        def lockfile
          @lockfile ||= get_original_file("mix.lock")
        end
      end
    end
  end
end
