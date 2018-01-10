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
            hex_package["releases"].
            select { |release| Gem::Version.correct?(release["version"]) }.
            map { |release| Gem::Version.new(release["version"]) }

          versions.reject(&:prerelease?).sort.last
        end

        def latest_resolvable_version
          @latest_resolvable_version ||= fetch_latest_resolvable_version
        end

        def updated_requirements
          # TODO
        end

        private

        def latest_version_resolvable_with_full_unlock?
          # Full unlock checks aren't implemented for Elixir (yet)
          false
        end

        def updated_dependencies_after_full_unlock
          raise NotImplementedError
        end

        def fetch_latest_resolvable_version
          @latest_resolvable_version ||=
            SharedHelpers.in_a_temporary_directory do |dir|
              File.write("mix.exs", prepared_mixfile_content)
              File.write("mix.lock", lockfile.content)
              FileUtils.cp(
                elixir_helper_load_deps_path,
                File.join(dir, "check_update.exs")
              )

              SharedHelpers.run_helper_subprocess(
                env: mix_env,
                command: "mix run #{elixir_helper_path}",
                function: "get_latest_resolvable_version",
                args: [dir, dependency.name]
              )
            end

          return if @latest_resolvable_version.nil?
          Gem::Version.new(latest_resolvable_version)
        end

        def prepared_mixfile_content
          old_requirement =
            dependency.requirements.find { |r| r.fetch(:file) == "mix.exs" }.
            fetch(:requirement)

          return mixfile.content unless old_requirement

          new_requirement =
            dependency.version.nil? ? ">= 0" : ">= #{dependency.version}"

          requirement_line_regex =
            /
              #{Regexp.escape(dependency.name)}.*
              #{Regexp.escape(old_requirement)}
            /x

          mixfile.content.gsub(requirement_line_regex) do |requirement_line|
            requirement_line.gsub(old_requirement, new_requirement)
          end
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

        def elixir_helper_load_deps_path
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

        def project_root
          File.join(File.dirname(__FILE__), "../../../..")
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
