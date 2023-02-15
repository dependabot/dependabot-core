# frozen_string_literal: true

require "excon"
require "toml-rb"
require "open3"
require "uri"
require "dependabot/dependency"
require "dependabot/errors"
require "dependabot/shared_helpers"
require "dependabot/python/file_parser"
require "dependabot/python/file_parser/python_requirement_parser"
require "dependabot/python/file_updater/pyproject_preparer"
require "dependabot/python/update_checker"
require "dependabot/python/version"
require "dependabot/python/requirement"
require "dependabot/python/native_helpers"
require "dependabot/python/python_versions"
require "dependabot/python/authed_url_builder"
require "dependabot/python/name_normaliser"

module Dependabot
  module Python
    class UpdateChecker
      # This class does version resolution for pyproject.toml files.
      class PoetryVersionResolver
        GIT_REFERENCE_NOT_FOUND_REGEX = /
          (?:'git'.*pypoetry-git-(?<name>.+?).{8}',
          'checkout',
          '(?<tag>.+?)'
          |
          Failed to checkout
          (?<tag>.+?)
          (?<url>.+?).git at '(?<tag>.+?)'
          |
          ...Failedtoclone
          (?<url>.+?).gitat'(?<tag>.+?)',
          verifyrefexistsonremote)
        /x # TODO: remove the first clause and | when py3.6 support is EoL
        GIT_DEPENDENCY_UNREACHABLE_REGEX = /
          (?:'\['git',
          \s+'clone',
          \s+'--recurse-submodules',
          \s+'(--)?',
          \s+'(?<url>.+?)'.*
          \s+exit\s+status\s+128
          |
          \s+Failed\sto\sclone
          \s+(?<url>.+?),
          \s+check\syour\sgit\sconfiguration)
        /mx # TODO: remove the first clause and | when py3.6 support is EoL

        attr_reader :dependency, :dependency_files, :credentials

        def initialize(dependency:, dependency_files:, credentials:)
          @dependency               = dependency
          @dependency_files         = dependency_files
          @credentials              = credentials
        end

        def latest_resolvable_version(requirement: nil)
          version_string =
            fetch_latest_resolvable_version_string(requirement: requirement)

          version_string.nil? ? nil : Python::Version.new(version_string)
        end

        def resolvable?(version:)
          @resolvable ||= {}
          return @resolvable[version] if @resolvable.key?(version)

          @resolvable[version] = if fetch_latest_resolvable_version_string(requirement: "==#{version}")
                                   true
                                 else
                                   false
                                 end
        rescue SharedHelpers::HelperSubprocessFailed => e
          raise unless e.message.include?("SolverProblemError") || # TODO: Remove once py3.6 is EoL
                       e.message.include?("version solving failed.")

          @resolvable[version] = false
        end

        private

        def fetch_latest_resolvable_version_string(requirement:)
          @latest_resolvable_version_string ||= {}
          return @latest_resolvable_version_string[requirement] if @latest_resolvable_version_string.key?(requirement)

          @latest_resolvable_version_string[requirement] ||=
            SharedHelpers.in_a_temporary_directory do
              SharedHelpers.with_git_configured(credentials: credentials) do
                write_temporary_dependency_files(updated_req: requirement)
                add_auth_env_vars

                language_version_manager.install_required_python

                # use system git instead of the pure Python dulwich
                unless language_version_manager.python_version&.start_with?("3.6")
                  run_poetry_command("pyenv exec poetry config experimental.system-git-client true")
                end

                # Shell out to Poetry, which handles everything for us.
                run_poetry_update_command

                updated_lockfile =
                  if File.exist?("poetry.lock") then File.read("poetry.lock")
                  else
                    File.read("pyproject.lock")
                  end
                updated_lockfile = TomlRB.parse(updated_lockfile)

                fetch_version_from_parsed_lockfile(updated_lockfile)
              rescue SharedHelpers::HelperSubprocessFailed => e
                handle_poetry_errors(e)
              end
            end
        end

        def fetch_version_from_parsed_lockfile(updated_lockfile)
          version =
            updated_lockfile.fetch("package", []).
            find { |d| d["name"] && normalise(d["name"]) == dependency.name }&.
            fetch("version")

          return version unless version.nil? && dependency.top_level?

          raise "No version in lockfile!"
        end

        def handle_poetry_errors(error)
          if error.message.gsub(/\s/, "").match?(GIT_REFERENCE_NOT_FOUND_REGEX)
            message = error.message.gsub(/\s/, "")
            match = message.match(GIT_REFERENCE_NOT_FOUND_REGEX)
            name = if (url = match.named_captures.fetch("url"))
                     File.basename(URI.parse(url).path)
                   else
                     message.match(GIT_REFERENCE_NOT_FOUND_REGEX).
                       named_captures.fetch("name")
                   end
            raise GitDependencyReferenceNotFound, name
          end

          if error.message.match?(GIT_DEPENDENCY_UNREACHABLE_REGEX)
            url = error.message.match(GIT_DEPENDENCY_UNREACHABLE_REGEX).
                  named_captures.fetch("url")
            raise GitDependenciesNotReachable, url
          end

          raise unless error.message.include?("SolverProblemError") ||
                       error.message.include?("PackageNotFound") ||
                       error.message.include?("version solving failed.")

          check_original_requirements_resolvable

          # If the original requirements are resolvable but the new version
          # would break Python version compatibility the update is blocked
          return if error.message.include?("support the following Python")

          # If any kind of other error is now occurring as a result of our
          # change then we want to hear about it
          raise
        end

        # Using `--lock` avoids doing an install.
        # Using `--no-interaction` avoids asking for passwords.
        def run_poetry_update_command
          run_poetry_command(
            "pyenv exec poetry update #{dependency.name} --lock --no-interaction",
            fingerprint: "pyenv exec poetry update <dependency_name> --lock --no-interaction"
          )
        end

        def check_original_requirements_resolvable
          return @original_reqs_resolvable if @original_reqs_resolvable

          SharedHelpers.in_a_temporary_directory do
            SharedHelpers.with_git_configured(credentials: credentials) do
              write_temporary_dependency_files(update_pyproject: false)

              run_poetry_update_command

              @original_reqs_resolvable = true
            rescue SharedHelpers::HelperSubprocessFailed => e
              raise unless e.message.include?("SolverProblemError") ||
                           e.message.include?("PackageNotFound") ||
                           e.message.include?("version solving failed.")

              msg = clean_error_message(e.message)
              raise DependencyFileNotResolvable, msg
            end
          end
        end

        def clean_error_message(message)
          # Redact any URLs, as they may include credentials
          message.gsub(/http.*?(?=\s)/, "<redacted>")
        end

        def write_temporary_dependency_files(updated_req: nil,
                                             update_pyproject: true)
          dependency_files.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, file.content)
          end

          # Overwrite the .python-version with updated content
          File.write(".python-version", language_version_manager.python_major_minor)

          # Overwrite the pyproject with updated content
          if update_pyproject
            File.write(
              "pyproject.toml",
              updated_pyproject_content(updated_requirement: updated_req)
            )
          else
            File.write("pyproject.toml", sanitized_pyproject_content)
          end
        end

        def add_auth_env_vars
          Python::FileUpdater::PyprojectPreparer.
            new(pyproject_content: pyproject.content).
            add_auth_env_vars(credentials)
        end

        def updated_pyproject_content(updated_requirement:)
          content = pyproject.content
          content = sanitize_pyproject_content(content)
          content = freeze_other_dependencies(content)
          content = set_target_dependency_req(content, updated_requirement)
          content
        end

        def sanitized_pyproject_content
          content = pyproject.content
          content = sanitize_pyproject_content(content)
          content
        end

        def sanitize_pyproject_content(pyproject_content)
          Python::FileUpdater::PyprojectPreparer.
            new(pyproject_content: pyproject_content).
            sanitize
        end

        def freeze_other_dependencies(pyproject_content)
          Python::FileUpdater::PyprojectPreparer.
            new(pyproject_content: pyproject_content, lockfile: lockfile).
            freeze_top_level_dependencies_except([dependency])
        end

        def set_target_dependency_req(pyproject_content, updated_requirement)
          return pyproject_content unless updated_requirement

          pyproject_object = TomlRB.parse(pyproject_content)
          poetry_object = pyproject_object.dig("tool", "poetry")

          Dependabot::Python::FileParser::PyprojectFilesParser::POETRY_DEPENDENCY_TYPES.each do |type|
            dependencies = poetry_object[type]
            next unless dependencies

            update_dependency_requirement(dependencies, updated_requirement)
          end

          # If this is a sub-dependency, add the new requirement
          unless dependency.requirements.find { |r| r[:file] == pyproject.name }
            poetry_object[subdep_type] ||= {}
            poetry_object[subdep_type][dependency.name] = updated_requirement
          end

          TomlRB.dump(pyproject_object)
        end

        def update_dependency_requirement(toml_node, requirement)
          names = toml_node.keys
          pkg_name = names.find { |nm| normalise(nm) == dependency.name }
          return unless pkg_name

          if toml_node[pkg_name].is_a?(Hash)
            toml_node[pkg_name]["version"] = requirement
          else
            toml_node[pkg_name] = requirement
          end
        end

        def subdep_type
          category =
            TomlRB.parse(lockfile.content).fetch("package", []).
            find { |dets| normalise(dets.fetch("name")) == dependency.name }.
            fetch("category")

          category == "dev" ? "dev-dependencies" : "dependencies"
        end

        def python_requirement_parser
          @python_requirement_parser ||=
            FileParser::PythonRequirementParser.new(
              dependency_files: dependency_files
            )
        end

        def language_version_manager
          @language_version_manager ||=
            LanguageVersionManager.new(
              python_requirement_parser: python_requirement_parser
            )
        end

        def pyproject
          dependency_files.find { |f| f.name == "pyproject.toml" }
        end

        def pyproject_lock
          dependency_files.find { |f| f.name == "pyproject.lock" }
        end

        def poetry_lock
          dependency_files.find { |f| f.name == "poetry.lock" }
        end

        def lockfile
          poetry_lock || pyproject_lock
        end

        def run_poetry_command(command, fingerprint: nil)
          start = Time.now
          command = SharedHelpers.escape_command(command)
          stdout, process = Open3.capture2e(command)
          time_taken = Time.now - start

          # Raise an error with the output from the shell session if poetry
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

        def normalise(name)
          NameNormaliser.normalise(name)
        end
      end
    end
  end
end
