# frozen_string_literal: true

require "toml-rb"

require "dependabot/file_updaters/python/pip"
require "dependabot/shared_helpers"

module Dependabot
  module FileUpdaters
    module Python
      class Pip
        class PipfileFileUpdater
          require_relative "pipfile_preparer"

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

            if file_changed?(pipfile)
              updated_files <<
                updated_file(file: pipfile, content: updated_pipfile_content)
            end

            if lockfile.content == updated_lockfile_content
              raise "Expected Pipfile.lock to change!"
            end

            updated_files <<
              updated_file(file: lockfile, content: updated_lockfile_content)

            updated_files
          end

          def updated_pipfile_content
            dependencies.
              select { |dep| requirement_changed?(pipfile, dep) }.
              reduce(pipfile.content.dup) do |content, dep|
                updated_requirement =
                  dep.requirements.find { |r| r[:file] == pipfile.name }.
                  fetch(:requirement)

                old_req =
                  dep.previous_requirements.
                  find { |r| r[:file] == pipfile.name }.
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
                pipfile_hash = pipfile_hash_for(updated_pipfile_content)
                original_reqs = parsed_lockfile["_meta"]["requires"]
                original_source = parsed_lockfile["_meta"]["sources"]

                new_lockfile = updated_lockfile_content_for(prepared_pipfile)
                new_lockfile_json = JSON.parse(new_lockfile)
                new_lockfile_json["_meta"]["hash"]["sha256"] = pipfile_hash
                new_lockfile_json["_meta"]["requires"] = original_reqs
                new_lockfile_json["_meta"]["sources"] = original_source

                JSON.pretty_generate(new_lockfile_json, indent: "    ").
                  gsub(/\{\n\s*\}/, "{}").
                  gsub(/\}\z/, "}\n")
              end
          end

          def prepared_pipfile
            content = updated_pipfile_content
            content = freeze_other_dependencies(content)
            content = freeze_dependencies_being_updated(content)
            content = add_private_sources(content)
            content
          end

          def freeze_other_dependencies(pipfile_content)
            PipfilePreparer.
              new(pipfile_content: pipfile_content).
              freeze_top_level_dependencies_except(dependencies, lockfile)
          end

          def freeze_dependencies_being_updated(pipfile_content)
            pipfile_object = TomlRB.parse(pipfile_content)

            dependencies.each do |dep|
              %w(packages dev-packages).each do |type|
                names = pipfile_object[type]&.keys || []
                pkg_name = names.find { |nm| normalise(nm) == dep.name }
                next unless pkg_name

                if pipfile_object[type][pkg_name].is_a?(Hash)
                  pipfile_object[type][pkg_name]["version"] =
                    "==#{dep.version}"
                else
                  pipfile_object[type][pkg_name] = "==#{dep.version}"
                end
              end
            end

            TomlRB.dump(pipfile_object)
          end

          def add_private_sources(pipfile_content)
            PipfilePreparer.
              new(pipfile_content: pipfile_content).
              replace_sources(credentials)
          end

          def updated_lockfile_content_for(pipfile_content)
            SharedHelpers.in_a_temporary_directory do
              write_temporary_dependency_files(pipfile_content)

              begin
                run_pipenv_command("PIPENV_YES=true PIPENV_MAX_RETRIES=2 "\
                                   "pyenv exec pipenv lock")
              rescue SharedHelpers::HelperSubprocessFailed => error
                # Workaround for https://github.com/pypa/pipenv/issues/2435
                raise unless error.message.include?("TypeError: expected")
                retry
              end

              File.read("Pipfile.lock")
            end
          end

          def run_pipenv_command(cmd)
            raw_response = nil
            IO.popen(cmd, err: %i(child out)) { |p| raw_response = p.read }

            # Raise an error with the output from the shell session if Pipenv
            # returns a non-zero status
            return if $CHILD_STATUS.success?
            raise SharedHelpers::HelperSubprocessFailed.new(raw_response, cmd)
          end

          def write_temporary_dependency_files(pipfile_content)
            dependency_files.each do |file|
              path = file.name
              FileUtils.mkdir_p(Pathname.new(path).dirname)
              File.write(path, file.content)
            end

            # Workaround for Pipenv bug
            FileUtils.mkdir_p("python_package.egg-info")

            # Overwrite the pipfile with updated content
            File.write("Pipfile", pipfile_content)
          end

          def pipfile_hash_for(pipfile_content)
            SharedHelpers.in_a_temporary_directory do |dir|
              File.write(File.join(dir, "Pipfile"), pipfile_content)
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
            @parsed_lockfile ||= JSON.parse(lockfile.content)
          end

          def pipfile
            @pipfile ||= dependency_files.find { |f| f.name == "Pipfile" }
          end

          def lockfile
            @lockfile ||= dependency_files.find { |f| f.name == "Pipfile.lock" }
          end
        end
      end
    end
  end
end
