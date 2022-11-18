# frozen_string_literal: true

require "toml-rb"
require "open3"
require "dependabot/dependency"
require "dependabot/python/requirement_parser"
require "dependabot/python/file_parser/python_requirement_parser"
require "dependabot/python/file_updater"
require "dependabot/shared_helpers"
require "dependabot/python/native_helpers"
require "dependabot/python/name_normaliser"

module Dependabot
  module Python
    class FileUpdater
      class PipfileFileUpdater
        require_relative "pipfile_preparer"
        require_relative "pipfile_manifest_updater"
        require_relative "setup_file_sanitizer"

        DEPENDENCY_TYPES = %w(packages dev-packages).freeze

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

          if pipfile.content != updated_pipfile_content
            updated_files <<
              updated_file(file: pipfile, content: updated_pipfile_content)
          end

          if lockfile
            raise "Expected Pipfile.lock to change!" if lockfile.content == updated_lockfile_content

            updated_files <<
              updated_file(file: lockfile, content: updated_lockfile_content)
          end

          updated_files += updated_generated_requirements_files
          updated_files
        end

        def updated_pipfile_content
          @updated_pipfile_content ||=
            PipfileManifestUpdater.new(
              dependencies: dependencies,
              manifest: pipfile
            ).updated_manifest_content
        end

        def updated_lockfile_content
          @updated_lockfile_content ||=
            updated_generated_files.fetch(:lockfile)
        end

        def generate_updated_requirements_files?
          return true if generated_requirements_files("default").any?

          generated_requirements_files("develop").any?
        end

        def generated_requirements_files(type)
          return [] unless lockfile

          pipfile_lock_deps = parsed_lockfile[type]&.keys&.sort || []
          pipfile_lock_deps = pipfile_lock_deps.map { |n| normalise(n) }
          return [] unless pipfile_lock_deps.any?

          regex = RequirementParser::INSTALL_REQ_WITH_REQUIREMENT

          # Find any requirement files that list the same dependencies as
          # the (old) Pipfile.lock. Any such files were almost certainly
          # generated using `pipenv lock -r`
          requirements_files.select do |req_file|
            deps = []
            req_file.content.scan(regex) { deps << Regexp.last_match }
            deps = deps.map { |m| normalise(m[:name]) }
            deps.sort == pipfile_lock_deps
          end
        end

        def updated_generated_requirements_files
          updated_files = []

          generated_requirements_files("default").each do |file|
            next if file.content == updated_req_content

            updated_files <<
              updated_file(file: file, content: updated_req_content)
          end

          generated_requirements_files("develop").each do |file|
            next if file.content == updated_dev_req_content

            updated_files <<
              updated_file(file: file, content: updated_dev_req_content)
          end

          updated_files
        end

        def updated_req_content
          updated_generated_files.fetch(:requirements_txt)
        end

        def updated_dev_req_content
          updated_generated_files.fetch(:dev_requirements_txt)
        end

        def prepared_pipfile_content
          content = updated_pipfile_content
          content = freeze_other_dependencies(content)
          content = freeze_dependencies_being_updated(content)
          content = add_private_sources(content)
          content = update_python_requirement(content)
          content
        end

        def freeze_other_dependencies(pipfile_content)
          PipfilePreparer.
            new(pipfile_content: pipfile_content, lockfile: lockfile).
            freeze_top_level_dependencies_except(dependencies)
        end

        def update_python_requirement(pipfile_content)
          PipfilePreparer.
            new(pipfile_content: pipfile_content).
            update_python_requirement(Helpers.python_major_minor(python_version))
        end

        # rubocop:disable Metrics/PerceivedComplexity
        def freeze_dependencies_being_updated(pipfile_content)
          pipfile_object = TomlRB.parse(pipfile_content)

          dependencies.each do |dep|
            DEPENDENCY_TYPES.each do |type|
              names = pipfile_object[type]&.keys || []
              pkg_name = names.find { |nm| normalise(nm) == dep.name }
              next unless pkg_name || subdep_type?(type)

              pkg_name ||= dependency.name
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
        # rubocop:enable Metrics/PerceivedComplexity

        def subdep_type?(type)
          return false if dependency.top_level?

          lockfile_type = Python::FileParser::DEPENDENCY_GROUP_KEYS.
                          find { |i| i.fetch(:pipfile) == type }.
                          fetch(:lockfile)

          JSON.parse(lockfile.content).
            fetch(lockfile_type, {}).
            keys.any? { |k| normalise(k) == dependency.name }
        end

        def add_private_sources(pipfile_content)
          PipfilePreparer.
            new(pipfile_content: pipfile_content).
            replace_sources(credentials)
        end

        def updated_generated_files
          @updated_generated_files ||=
            SharedHelpers.in_a_temporary_directory do
              SharedHelpers.with_git_configured(credentials: credentials) do
                write_temporary_dependency_files(prepared_pipfile_content)
                install_required_python

                # Initialize a git repo to appease pip-tools
                command = SharedHelpers.escape_command("git init")
                IO.popen(command, err: %i(child out)) if setup_files.any?

                run_pipenv_command(
                  "pyenv exec pipenv lock"
                )

                result = { lockfile: File.read("Pipfile.lock") }
                result[:lockfile] = post_process_lockfile(result[:lockfile])

                # Generate updated requirement.txt entries, if needed.
                if generate_updated_requirements_files?
                  generate_updated_requirements_files

                  result[:requirements_txt] = File.read("req.txt")
                  result[:dev_requirements_txt] = File.read("dev-req.txt")
                end

                result
              end
            end
        end

        def post_process_lockfile(updated_lockfile_content)
          pipfile_hash = pipfile_hash_for(updated_pipfile_content)
          original_reqs = parsed_lockfile["_meta"]["requires"]
          original_source = parsed_lockfile["_meta"]["sources"]

          new_lockfile = updated_lockfile_content.dup
          new_lockfile_json = JSON.parse(new_lockfile)
          new_lockfile_json["_meta"]["hash"]["sha256"] = pipfile_hash
          new_lockfile_json["_meta"]["requires"] = original_reqs
          new_lockfile_json["_meta"]["sources"] = original_source

          JSON.pretty_generate(new_lockfile_json, indent: "    ").
            gsub(/\{\n\s*\}/, "{}").
            gsub(/\}\z/, "}\n")
        end

        def generate_updated_requirements_files
          req_content = run_pipenv_command(
            "pyenv exec pipenv lock -r"
          )
          File.write("req.txt", req_content)

          dev_req_content = run_pipenv_command(
            "pyenv exec pipenv lock -r -d"
          )
          File.write("dev-req.txt", dev_req_content)
        end

        def run_command(command, env: {})
          start = Time.now
          command = SharedHelpers.escape_command(command)
          stdout, _, process = Open3.capture3(env, command)
          time_taken = Time.now - start

          # Raise an error with the output from the shell session if Pipenv
          # returns a non-zero status
          return stdout if process.success?

          raise SharedHelpers::HelperSubprocessFailed.new(
            message: stdout,
            error_context: {
              command: command,
              time_taken: time_taken,
              process_exit_value: process.to_s
            }
          )
        end

        def run_pipenv_command(command, env: pipenv_env_variables)
          run_command("pyenv local #{Helpers.python_major_minor(python_version)}")
          run_command(command, env: env)
        end

        def write_temporary_dependency_files(pipfile_content)
          dependency_files.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, file.content)
          end

          # Overwrite the .python-version with updated content
          File.write(".python-version", Helpers.python_major_minor(python_version))

          setup_files.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, sanitized_setup_file_content(file))
          end

          setup_cfg_files.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, "[metadata]\nname = sanitized-package\n")
          end

          # Overwrite the pipfile with updated content
          File.write("Pipfile", pipfile_content)
        end

        def install_required_python
          # Initialize a git repo to appease pip-tools
          begin
            run_command("git init") if setup_files.any?
          rescue Dependabot::SharedHelpers::HelperSubprocessFailed
            nil
          end

          Helpers.install_required_python(python_version)
        end

        def sanitized_setup_file_content(file)
          @sanitized_setup_file_content ||= {}
          return @sanitized_setup_file_content[file.name] if @sanitized_setup_file_content[file.name]

          @sanitized_setup_file_content[file.name] =
            SetupFileSanitizer.
            new(setup_file: file, setup_cfg: setup_cfg(file)).
            sanitized_content
        end

        def python_version
          @python_version ||= python_version_from_supported_versions
        end

        def python_version_from_supported_versions
          requirement_string =
            if @using_python_two then "2.7.*"
            elsif user_specified_python_requirement
              parts = user_specified_python_requirement.split(".")
              parts.fill("*", (parts.length)..2).join(".")
            else
              PythonVersions::PRE_INSTALLED_PYTHON_VERSIONS.first
            end

          # Ideally, the requirement is satisfied by a Python version we support
          requirement =
            Python::Requirement.requirements_array(requirement_string).first
          version =
            PythonVersions::SUPPORTED_VERSIONS_TO_ITERATE.
            find { |v| requirement.satisfied_by?(Python::Version.new(v)) }
          return version if version

          # If not, and changing the patch version would fix things, we do that
          # as the patch version is unlikely to affect resolution
          requirement =
            Python::Requirement.new(requirement_string.gsub(/\.\d+$/, ".*"))
          version =
            PythonVersions::SUPPORTED_VERSIONS_TO_ITERATE.
            find { |v| requirement.satisfied_by?(Python::Version.new(v)) }
          return version if version

          # Otherwise we have to raise, giving details of the Python versions
          # that Dependabot supports
          msg = "Dependabot detected the following Python requirement " \
                "for your project: '#{requirement_string}'.\n\nCurrently, the " \
                "following Python versions are supported in Dependabot: " \
                "#{PythonVersions::SUPPORTED_VERSIONS.join(', ')}."
          raise DependencyFileNotResolvable, msg
        end

        def user_specified_python_requirement
          python_requirement_parser.user_specified_requirements.first
        end

        def python_requirement_parser
          @python_requirement_parser ||=
            FileParser::PythonRequirementParser.new(
              dependency_files: dependency_files
            )
        end

        def setup_cfg(file)
          dependency_files.find do |f|
            f.name == file.name.sub(/\.py$/, ".cfg")
          end
        end

        def pipfile_hash_for(pipfile_content)
          SharedHelpers.in_a_temporary_directory do |dir|
            File.write(File.join(dir, "Pipfile"), pipfile_content)
            SharedHelpers.run_helper_subprocess(
              command: "pyenv exec python #{NativeHelpers.python_helper_path}",
              function: "get_pipfile_hash",
              args: [dir]
            )
          end
        end

        def updated_file(file:, content:)
          updated_file = file.dup
          updated_file.content = content
          updated_file
        end

        def normalise(name)
          NameNormaliser.normalise(name)
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

        def setup_files
          dependency_files.select { |f| f.name.end_with?("setup.py") }
        end

        def setup_cfg_files
          dependency_files.select { |f| f.name.end_with?("setup.cfg") }
        end

        def requirements_files
          dependency_files.select { |f| f.name.end_with?(".txt") }
        end

        def pipenv_env_variables
          {
            "PIPENV_YES" => "true",       # Install new Python ver if needed
            "PIPENV_MAX_RETRIES" => "3",  # Retry timeouts
            "PIPENV_NOSPIN" => "1",       # Don't pollute logs with spinner
            "PIPENV_TIMEOUT" => "600",    # Set install timeout to 10 minutes
            "PIP_DEFAULT_TIMEOUT" => "60" # Set pip timeout to 1 minute
          }
        end
      end
    end
  end
end
