# frozen_string_literal: true

require "dependabot/file_updaters/base"
require "dependabot/shared_helpers"

module Dependabot
  module FileUpdaters
    module Elixir
      class Hex < Base
        def self.updated_files_regex
          [
            /^mix\.exs$/,
            /^mix\.lock$/
          ]
        end

        def updated_dependency_files
          updated_files = []

          mixfiles.each do |file|
            if file_changed?(file)
              updated_files <<
                updated_file(file: file, content: updated_mixfile_content(file))
            end
          end

          if lockfile
            updated_files <<
              updated_file(file: lockfile, content: updated_lockfile_content)
          end

          updated_files
        end

        private

        def dependency
          # For now, we'll only ever be updating a single dependency for Elixir
          dependencies.first
        end

        def check_required_files
          raise "No mix.exs!" unless get_original_file("mix.exs")
        end

        def mixfiles
          dependency_files.select { |f| f.name.end_with?("mix.exs") }
        end

        def lockfile
          @lockfile ||= get_original_file("mix.lock")
        end

        def updated_lockfile_content
          @updated_lockfile_content ||=
            SharedHelpers.in_a_temporary_directory do
              write_temporary_dependency_files
              FileUtils.cp(elixir_helper_do_update_path, "do_update.exs")

              SharedHelpers.run_helper_subprocess(
                env: mix_env,
                command: "mix run #{elixir_helper_path}",
                function: "get_updated_lockfile",
                args: [Dir.pwd, dependency.name]
              )
            end
        end

        def write_temporary_dependency_files
          mixfiles.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(
              path,
              sanitize_mixfile(updated_mixfile_content(file))
            )
          end
          File.write("mix.lock", lockfile.content)
        end

        def updated_mixfile_content(file)
          dependencies.
            select { |dep| requirement_changed?(file, dep) }.
            reduce(file.content.dup) do |content, dep|
              updated_content = content
              updated_content = update_requirement(
                content: updated_content,
                filename: file.name,
                dependency: dep
              )
              updated_content = update_git_pin(
                content: updated_content,
                filename: file.name,
                dependency: dep
              )

              raise "Expected content to change!" if content == updated_content
              updated_content
            end
        end

        def update_requirement(content:, filename:, dependency:)
          updated_req =
            dependency.requirements.find { |r| r[:file] == filename }.
            fetch(:requirement)

          old_req =
            dependency.previous_requirements.find { |r| r[:file] == filename }.
            fetch(:requirement)

          return content unless old_req

          declaration_regex =
            /:#{Regexp.escape(dependency.name)},.*#{Regexp.escape(old_req)}/

          content.gsub(declaration_regex) do |declaration|
            declaration.gsub(old_req, updated_req)
          end
        end

        def update_git_pin(content:, filename:, dependency:)
          updated_pin =
            dependency.requirements.find { |r| r[:file] == filename }&.
            dig(:source, :ref)

          old_pin =
            dependency.previous_requirements.find { |r| r[:file] == filename }&.
            dig(:source, :ref)

          return content unless old_pin

          requirement_line_regex =
            /
              :#{Regexp.escape(dependency.name)},.*
              (?:ref|tag):\s+["']#{Regexp.escape(old_pin)}["']
            /x

          content.gsub(requirement_line_regex) do |requirement_line|
            requirement_line.gsub(old_pin, updated_pin)
          end
        end

        def sanitize_mixfile(content)
          content.
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

        def elixir_helper_do_update_path
          File.join(project_root, "helpers/elixir/bin/do_update.exs")
        end

        def project_root
          File.join(File.dirname(__FILE__), "../../../..")
        end
      end
    end
  end
end
