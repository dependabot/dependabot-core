# frozen_string_literal: true

require "toml-rb"

require "dependabot/file_updaters/base"
require "dependabot/file_fetchers/python/pipfile"
require "dependabot/shared_helpers"

module Dependabot
  module FileUpdaters
    module Python
      class Pipfile < Dependabot::FileUpdaters::Base
        def self.updated_files_regex
          [
            /^Pipfile$/,
            /^Pipfile\.lock$/
          ]
        end

        def updated_dependency_files
          [
            updated_file(
              file: pipfile,
              content: updated_pipfile_content
            ),
            updated_file(
              file: lockfile,
              content: updated_lockfile_content
            )
          ]
        end

        private

        def check_required_files
          %w(Pipfile Pipfile.lock).each do |filename|
            raise "No #{filename}!" unless get_original_file(filename)
          end
        end

        def pipfile
          @pipfile ||= get_original_file("Pipfile")
        end

        def lockfile
          @lockfile ||= get_original_file("Pipfile.lock")
        end

        def updated_pipfile_content
          dependencies.
            select { |dep| requirement_changed?(pipfile, dep) }.
            reduce(pipfile.content.dup) do |content, dep|
              updated_requirement =
                dep.requirements.find { |r| r[:file] == pipfile.name }.
                fetch(:requirement)

              old_req =
                dep.previous_requirements.find { |r| r[:file] == pipfile.name }.
                fetch(:requirement)

              updated_content =
                content.gsub(declaration_regex(dep)) do |line|
                  line.gsub(old_req, updated_requirement)
                end

              raise "Expected content to change!" if content == updated_content
              updated_content
            end
        end

        def updated_lockfile_content
          @updated_lockfile_content ||=
            begin
              pipfile_hash = pipfile_hash_for(updated_pipfile_content)
              updated_lockfile =
                updated_lockfile_content_for(frozen_pipfile_content)
              original_env_markers =
                lockfile.content.match(/environment-markers.*pipfile-spec/m).
                to_s

              updated_lockfile.sub(
                /"sha256": ".*?"/,
                %("sha256": "#{pipfile_hash}")
              ).sub(/environment-markers.*pipfile-spec/m, original_env_markers)
            end
        end

        def frozen_pipfile_content
          frozen_pipfile_json = TomlRB.parse(updated_pipfile_content)
          parsed_lockfile = JSON.parse(lockfile.content)

          frozen_pipfile_json.dup.fetch("packages", {}).each_key do |nm|
            next if dependencies.map(&:name).include?(nm)
            version =
              parsed_lockfile.dig("default", normalised_name(nm), "version")
            frozen_pipfile_json["packages"][nm] = version
          end
          frozen_pipfile_json.dup.fetch("dev-packages", {}).each_key do |nm|
            next if dependencies.map(&:name).include?(nm)
            version =
              parsed_lockfile.dig("develop", normalised_name(nm), "version")
            frozen_pipfile_json["dev-packages"][nm] = version
          end

          TomlRB.dump(frozen_pipfile_json)
        end

        def updated_lockfile_content_for(pipfile_content)
          SharedHelpers.in_a_temporary_directory do |dir|
            File.write(File.join(dir, "Pipfile.lock"), lockfile.content)
            File.write(File.join(dir, "Pipfile"), pipfile_content)

            SharedHelpers.run_helper_subprocess(
              command: "python #{python_helper_path}",
              function: "update_pipfile",
              args: [dir]
            )
          end.fetch("Pipfile.lock")
        end

        def pipfile_hash_for(pipfile_content)
          SharedHelpers.in_a_temporary_directory do |dir|
            File.write(File.join(dir, "Pipfile"), pipfile_content)
            SharedHelpers.run_helper_subprocess(
              command: "python #{python_helper_path}",
              function: "get_pipfile_hash",
              args: [dir]
            )
          end
        end

        def normalised_name(name)
          name.downcase.tr("_", "-")
        end

        def declaration_regex(dep)
          /(?:^|["'])#{Regexp.escape(dep.name)}["']?\s*=.*$/
        end

        def python_helper_path
          project_root = File.join(File.dirname(__FILE__), "../../../..")
          File.join(project_root, "helpers/python/run.py")
        end
      end
    end
  end
end
