# frozen_string_literal: true

require "dependabot/file_updaters/base"
require "dependabot/shared_helpers"

module Dependabot
  module FileUpdaters
    module Elixir
      class Hex < Base
        require_relative "hex/mixfile_requirement_updater"
        require_relative "hex/mixfile_git_pin_updater"
        require_relative "hex/mixfile_sanitizer"

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
                args: [Dir.pwd, dependency.name, organization_credentials]
              )
            end

          post_process_lockfile(@updated_lockfile_content)
        end

        def post_process_lockfile(content)
          return content unless lockfile.content.start_with?("%{\"")
          return content if content.start_with?("%{\"")

          # Substitute back old file beginning and ending
          content.sub(/\A%\{\n  "/, "%{\"").sub(/\},\n\}/, "}}")
        end

        def write_temporary_dependency_files
          mixfiles.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, mixfile_content_for_lockfile_generation(file))
          end
          File.write("mix.lock", lockfile.content)
        end

        def mixfile_content_for_lockfile_generation(file)
          content = updated_mixfile_content(file)
          sanitize_mixfile(content)
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

          MixfileRequirementUpdater.new(
            dependency_name: dependency.name,
            mixfile_content: content,
            previous_requirement: old_req,
            updated_requirement: updated_req
          ).updated_content
        end

        def update_git_pin(content:, filename:, dependency:)
          updated_pin =
            dependency.requirements.find { |r| r[:file] == filename }&.
            dig(:source, :ref)

          old_pin =
            dependency.previous_requirements.find { |r| r[:file] == filename }&.
            dig(:source, :ref)

          return content unless old_pin
          return content if old_pin == updated_pin

          MixfileGitPinUpdater.new(
            dependency_name: dependency.name,
            mixfile_content: content,
            previous_pin: old_pin,
            updated_pin: updated_pin
          ).updated_content
        end

        def sanitize_mixfile(content)
          MixfileSanitizer.new(mixfile_content: content).sanitized_content
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

        def organization_credentials
          credentials.select { |cred| cred["type"] == "hex_organization" }.
            flat_map { |cred| [cred["organization"], cred["token"]] }
        end
      end
    end
  end
end
