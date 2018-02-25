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
              package_manager: "hex"
            )
          end
        end

        private

        def dependency_versions
          SharedHelpers.in_a_temporary_directory do
            File.write("mix.exs", sanitized_mixfile)
            File.write("mix.lock", lockfile.content)
            FileUtils.cp(elixir_helper_parse_deps_path, "parse_deps.exs")

            SharedHelpers.run_helper_subprocess(
              env: mix_env,
              command: "mix run #{elixir_helper_path}",
              function: "parse",
              args: [Dir.pwd]
            )
          end
        end

        def sanitized_mixfile
          mixfile.content.
            gsub(/File\.read!\(.*?\)/, '"0.0.1"').
            gsub(/File\.read\(.*?\)/, '{:ok, "0.0.1"}')
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

        def elixir_helper_parse_deps_path
          File.join(project_root, "helpers/elixir/bin/parse_deps.exs")
        end

        def required_files
          Dependabot::FileFetchers::Elixir::Hex.required_files
        end

        def check_required_files
          %w(mix.exs mix.lock).each do |filename|
            raise "No #{filename}!" unless get_original_file(filename)
          end
        end

        def project_root
          File.join(File.dirname(__FILE__), "../../../..")
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
