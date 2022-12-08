# frozen_string_literal: true

require "toml-rb"
require "open3"
require "dependabot/dependency"
require "dependabot/shared_helpers"
require "dependabot/python/helpers"
require "dependabot/python/version"
require "dependabot/python/requirement"
require "dependabot/python/python_versions"
require "dependabot/python/file_parser/python_requirement_parser"
require "dependabot/python/file_updater"
require "dependabot/python/native_helpers"
require "dependabot/python/name_normaliser"

module Dependabot
  module Python
    class FileUpdater
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

          raise "Expected lockfile to change!" if lockfile && lockfile.content == updated_lockfile_content

          if lockfile
            updated_files <<
              updated_file(file: lockfile, content: updated_lockfile_content)
          end

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
              new_lockfile = updated_lockfile_content_for(prepared_pyproject)

              tmp_hash =
                TomlRB.parse(new_lockfile)["metadata"]["content-hash"]
              correct_hash = pyproject_hash_for(updated_pyproject_content)

              new_lockfile.gsub(tmp_hash, correct_hash)
            end
        end

        def prepared_pyproject
          @prepared_pyproject ||=
            begin
              content = updated_pyproject_content
              content = sanitize(content)
              content = freeze_other_dependencies(content)
              content = freeze_dependencies_being_updated(content)
              content = update_python_requirement(content)
              content
            end
        end

        def freeze_other_dependencies(pyproject_content)
          PyprojectPreparer.
            new(pyproject_content: pyproject_content, lockfile: lockfile).
            freeze_top_level_dependencies_except(dependencies)
        end

        def freeze_dependencies_being_updated(pyproject_content)
          pyproject_object = TomlRB.parse(pyproject_content)
          poetry_object = pyproject_object.fetch("tool").fetch("poetry")

          dependencies.each do |dep|
            if dep.requirements.find { |r| r[:file] == pyproject.name }
              lock_declaration_to_new_version!(poetry_object, dep)
            else
              create_declaration_at_new_version!(poetry_object, dep)
            end
          end

          TomlRB.dump(pyproject_object)
        end

        def update_python_requirement(pyproject_content)
          PyprojectPreparer.
            new(pyproject_content: pyproject_content).
            update_python_requirement(Helpers.python_major_minor(python_version))
        end

        def lock_declaration_to_new_version!(poetry_object, dep)
          Dependabot::Python::FileParser::PyprojectFilesParser::POETRY_DEPENDENCY_TYPES.each do |type|
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

        def create_declaration_at_new_version!(poetry_object, dep)
          poetry_object[subdep_type] ||= {}
          poetry_object[subdep_type][dependency.name] = dep.version
        end

        def subdep_type
          category =
            TomlRB.parse(lockfile.content).fetch("package", []).
            find { |dets| normalise(dets.fetch("name")) == dependency.name }.
            fetch("category")

          category == "dev" ? "dev-dependencies" : "dependencies"
        end

        def sanitize(pyproject_content)
          PyprojectPreparer.
            new(pyproject_content: pyproject_content).
            sanitize
        end

        def updated_lockfile_content_for(pyproject_content)
          SharedHelpers.in_a_temporary_directory do
            SharedHelpers.with_git_configured(credentials: credentials) do
              write_temporary_dependency_files(pyproject_content)
              add_auth_env_vars

              Helpers.install_required_python(python_version)

              # use system git instead of the pure Python dulwich
              unless python_version&.start_with?("3.6")
                run_poetry_command("pyenv exec poetry config experimental.system-git-client true")
              end

              run_poetry_update_command

              return File.read("poetry.lock") if File.exist?("poetry.lock")

              File.read("pyproject.lock")
            end
          end
        end

        # Using `--lock` avoids doing an install.
        # Using `--no-interaction` avoids asking for passwords.
        def run_poetry_update_command
          run_poetry_command(
            "pyenv exec poetry update #{dependency.name} --lock --no-interaction",
            fingerprint: "pyenv exec poetry update <dependency_name> --lock --no-interaction"
          )
        end

        def run_poetry_command(command, fingerprint: nil)
          start = Time.now
          command = SharedHelpers.escape_command(command)
          stdout, process = Open3.capture2e(command)
          time_taken = Time.now - start

          # Raise an error with the output from the shell session if Pipenv
          # returns a non-zero status
          return if process.success?

          raise SharedHelpers::HelperSubprocessFailed.new(
            message: stdout,
            error_context: {
              command: command,
              fingerprint: fingerprint,
              time_taken: time_taken,
              process_exit_value: process.to_s
            }
          )
        end

        def write_temporary_dependency_files(pyproject_content)
          dependency_files.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, file.content)
          end

          # Overwrite the .python-version with updated content
          File.write(".python-version", Helpers.python_major_minor(python_version)) if python_version

          # Overwrite the pyproject with updated content
          File.write("pyproject.toml", pyproject_content)
        end

        def add_auth_env_vars
          Python::FileUpdater::PyprojectPreparer.
            new(pyproject_content: pyproject.content).
            add_auth_env_vars(credentials)
        end

        def python_version
          requirements = python_requirement_parser.user_specified_requirements
          requirements = requirements.
                         map { |r| Python::Requirement.requirements_array(r) }

          PythonVersions::SUPPORTED_VERSIONS_TO_ITERATE.find do |version|
            requirements.all? do |reqs|
              reqs.any? { |r| r.satisfied_by?(Python::Version.new(version)) }
            end
          end
        end

        def python_requirement_parser
          @python_requirement_parser ||=
            FileParser::PythonRequirementParser.new(
              dependency_files: dependency_files
            )
        end

        def pre_installed_python?(version)
          PythonVersions::PRE_INSTALLED_PYTHON_VERSIONS.include?(version)
        end

        def pyproject_hash_for(pyproject_content)
          SharedHelpers.in_a_temporary_directory do |dir|
            SharedHelpers.with_git_configured(credentials: credentials) do
              write_temporary_dependency_files(pyproject_content)

              SharedHelpers.run_helper_subprocess(
                command: "pyenv exec python #{python_helper_path}",
                function: "get_pyproject_hash",
                args: [dir]
              )
            end
          end
        end

        def declaration_regex(dep)
          escaped_name = Regexp.escape(dep.name).gsub("\\-", "[-_.]")
          /(?:^\s*|["'])#{escaped_name}["']?\s*=.*$/i
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

        def normalise(name)
          NameNormaliser.normalise(name)
        end

        def pyproject
          @pyproject ||=
            dependency_files.find { |f| f.name == "pyproject.toml" }
        end

        def lockfile
          @lockfile ||= pyproject_lock || poetry_lock
        end

        def python_helper_path
          NativeHelpers.python_helper_path
        end

        def pyproject_lock
          dependency_files.find { |f| f.name == "pyproject.lock" }
        end

        def poetry_lock
          dependency_files.find { |f| f.name == "poetry.lock" }
        end
      end
    end
  end
end
