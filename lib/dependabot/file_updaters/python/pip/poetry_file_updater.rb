# frozen_string_literal: true

require "toml-rb"

require "dependabot/file_updaters/python/pip"
require "dependabot/shared_helpers"

module Dependabot
  module FileUpdaters
    module Python
      class Pip
        class PoetryFileUpdater
          require_relative "pyproject_preparer"

          attr_reader :dependencies, :dependency_files, :credentials

          def initialize(dependencies:, dependency_files:, credentials:)
            @dependencies = dependencies
            @dependency_files = dependency_files
            @credentials = credentials
          end

          def updated_dependency_files
            return @updated_dependency_files if @update_already_attempted

            @update_already_attempted = true
            @updated_dependency_files ||= fetch_updated_dependency_files
          end

          private

          def dependency
            # For now, we'll only ever be updating a single dependency
            dependencies.first
          end

          def fetch_updated_dependency_files
            updated_files = []

            if file_changed?(pyproject)
              updated_files <<
                updated_file(
                  file: pyproject,
                  content: updated_pyproject_content
                )
            end

            if lockfile && lockfile.content == updated_lockfile_content
              raise "Expected pyproject.lock to change!"
            end

            updated_files <<
              updated_file(file: lockfile, content: updated_lockfile_content)

            updated_files
          end

          def updated_pyproject_content
            dependencies.
              select { |dep| requirement_changed?(pyproject, dep) }.
              reduce(pyproject.content.dup) do |content, dep|
                updated_requirement =
                  dep.requirements.find { |r| r[:file] == pyproject.name }.
                  fetch(:requirement)

                old_req =
                  dep.previous_requirements.
                  find { |r| r[:file] == pyproject.name }.
                  fetch(:requirement)

                updated_content =
                  content.gsub(declaration_regex(dep)) do |line|
                    line.gsub(old_req, updated_requirement)
                  end

                raise "Content did not change!" if content == updated_content
                updated_content
              end
          end

          def updated_lockfile_content
            @updated_lockfile_content ||=
              begin
                original_hash = parsed_lockfile["metadata"]["content-hash"]
                updated_hash = pyproject_hash_for(updated_pyproject_content)

                new_lockfile = updated_lockfile_content_for(prepared_pyproject)
                new_lockfile.gsub(original_hash, updated_hash)
              end
          end

          def prepared_pyproject
            content = updated_pyproject_content
            content = freeze_other_dependencies(content)
            content = freeze_dependencies_being_updated(content)
            content = add_private_sources(content)
            content
          end

          def freeze_other_dependencies(pyproject_content)
            PyprojectPreparer.
              new(pyproject_content: pyproject_content).
              freeze_top_level_dependencies_except(dependencies, lockfile)
          end

          def freeze_dependencies_being_updated(pyproject_content)
            pyproject_object = TomlRB.parse(pyproject_content)
            poetry_object = pyproject_object.fetch("tool").fetch("poetry")

            dependencies.each do |dep|
              %w(dependencies dev-dependencies).each do |type|
                names = poetry_object[type]&.keys || []
                pkg_name = names.find { |nm| normalise(nm) == dep.name }
                next unless pkg_name

                if poetry_object[type][pkg_name].is_a?(Hash)
                  poetry_object[type][pkg_name]["version"] = dep.version
                else
                  poetry_object[type][pkg_name] = dep.version
                end
              end
            end

            TomlRB.dump(pyproject_object)
          end

          def add_private_sources(pyproject_content)
            PyprojectPreparer.
              new(pyproject_content: pyproject_content).
              replace_sources(credentials)
          end

          def updated_lockfile_content_for(pyproject_content)
            SharedHelpers.in_a_temporary_directory do
              write_temporary_dependency_files(pyproject_content)

              run_poetry_command("poetry lock")

              File.read("pyproject.lock")
            end
          end

          def run_poetry_command(cmd)
            raw_response = nil
            IO.popen(cmd, err: %i(child out)) { |p| raw_response = p.read }

            # Raise an error with the output from the shell session if Pipenv
            # returns a non-zero status
            return if $CHILD_STATUS.success?
            raise SharedHelpers::HelperSubprocessFailed.new(raw_response, cmd)
          end

          def write_temporary_dependency_files(pyproject_content)
            dependency_files.each do |file|
              path = file.name
              FileUtils.mkdir_p(Pathname.new(path).dirname)
              File.write(path, file.content)
            end

            # Overwrite the pyproject with updated content
            File.write("pyproject.toml", pyproject_content)
          end

          def pyproject_hash_for(pyproject_content)
            SharedHelpers.in_a_temporary_directory do |dir|
              File.write(File.join(dir, "Pipfile"), pyproject_content)
              SharedHelpers.run_helper_subprocess(
                command:  "pyenv exec python #{python_helper_path}",
                function: "get_pipfile_hash",
                args: [dir]
              )
            end
          end

          def declaration_regex(dep)
            escaped_name = Regexp.escape(dep.name).gsub("\\-", "[-_.]")
            /(?:^|["'])#{escaped_name}["']?\s*=.*$/i
          end

          def file_changed?(file)
            dependencies.any? { |dep| requirement_changed?(file, dep) }
          end

          def requirement_changed?(file, dependency)
            changed_requirements =
              dependency.requirements - dependency.previous_requirements

            changed_requirements.any? { |f| f[:file] == file.name }
          end

          def updated_file(file:, content:)
            updated_file = file.dup
            updated_file.content = content
            updated_file
          end

          def python_helper_path
            project_root = File.join(File.dirname(__FILE__), "../../../../..")
            File.join(project_root, "helpers/python/run.py")
          end

          # See https://www.python.org/dev/peps/pep-0503/#normalized-names
          def normalise(name)
            name.downcase.tr("_", "-").tr(".", "-")
          end

          def parsed_lockfile
            @parsed_lockfile ||= TomlRB.parse(lockfile.content)
          end

          def pyproject
            @pyproject ||=
              dependency_files.find { |f| f.name == "pyproject.toml" }
          end

          def lockfile
            @lockfile ||=
              dependency_files.find { |f| f.name == "pyproject.lock" }
          end
        end
      end
    end
  end
end
