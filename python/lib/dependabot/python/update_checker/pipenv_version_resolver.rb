# typed: true
# frozen_string_literal: true

require "excon"
require "open3"
require "dependabot/dependency"
require "dependabot/errors"
require "dependabot/shared_helpers"
require "dependabot/python/file_parser"
require "dependabot/python/file_parser/python_requirement_parser"
require "dependabot/python/file_updater/pipfile_preparer"
require "dependabot/python/file_updater/setup_file_sanitizer"
require "dependabot/python/update_checker"
require "dependabot/python/native_helpers"
require "dependabot/python/pipenv_runner"
require "dependabot/python/version"

module Dependabot
  module Python
    class UpdateChecker
      class PipenvVersionResolver
        GIT_DEPENDENCY_UNREACHABLE_REGEX = /git clone --filter=blob:none --quiet (?<url>[^\s]+).*/
        GIT_REFERENCE_NOT_FOUND_REGEX = /git checkout -q (?<tag>[^\s]+).*/
        PIPENV_INSTALLATION_ERROR_NEW = "Getting requirements to build wheel exited with 1"

        # Can be removed when Python 3.11 support is dropped
        PIPENV_INSTALLATION_ERROR_OLD = Regexp.quote("python setup.py egg_info exited with 1")

        PIPENV_INSTALLATION_ERROR = /#{PIPENV_INSTALLATION_ERROR_NEW}|#{PIPENV_INSTALLATION_ERROR_OLD}/
        PIPENV_INSTALLATION_ERROR_REGEX =
          /[\s\S]*Collecting\s(?<name>.+)\s\(from\s-r.+\)[\s\S]*(#{PIPENV_INSTALLATION_ERROR})/

        PIPENV_RANGE_WARNING = /Warning:\sPython\s[<>].* was not found/

        attr_reader :dependency
        attr_reader :dependency_files
        attr_reader :credentials
        attr_reader :repo_contents_path

        def initialize(dependency:, dependency_files:, credentials:, repo_contents_path:)
          @dependency               = dependency
          @dependency_files         = dependency_files
          @credentials              = credentials
          @repo_contents_path       = repo_contents_path
        end

        def latest_resolvable_version(requirement: nil)
          version_string =
            fetch_latest_resolvable_version_string(requirement: requirement)

          version_string.nil? ? nil : Python::Version.new(version_string)
        end

        def resolvable?(version:)
          @resolvable ||= {}
          return @resolvable[version] if @resolvable.key?(version)

          @resolvable[version] = !!fetch_latest_resolvable_version_string(requirement: "==#{version}")
        end

        private

        def fetch_latest_resolvable_version_string(requirement:)
          @latest_resolvable_version_string ||= {}
          return @latest_resolvable_version_string[requirement] if @latest_resolvable_version_string.key?(requirement)

          @latest_resolvable_version_string[requirement] ||=
            SharedHelpers.in_a_temporary_repo_directory(base_directory, repo_contents_path) do
              SharedHelpers.with_git_configured(credentials: credentials) do
                write_temporary_dependency_files
                install_required_python

                pipenv_runner.run_upgrade_and_fetch_version(requirement)
              end
            rescue SharedHelpers::HelperSubprocessFailed => e
              handle_pipenv_errors(e)
            end
        end

        # rubocop:disable Metrics/CyclomaticComplexity
        # rubocop:disable Metrics/PerceivedComplexity
        # rubocop:disable Metrics/AbcSize
        # rubocop:disable Metrics/MethodLength
        def handle_pipenv_errors(error)
          if error.message.include?("no version found at all") ||
             error.message.include?("Invalid specifier:") ||
             error.message.include?("Max retries exceeded")
            msg = clean_error_message(error.message)
            raise if msg.empty?

            raise DependencyFileNotResolvable, msg
          end

          if error.message.match?(PIPENV_RANGE_WARNING)
            msg = "Pipenv does not support specifying Python ranges " \
                  "(see https://github.com/pypa/pipenv/issues/1050 for more " \
                  "details)."
            raise DependencyFileNotResolvable, msg
          end

          if error.message.match?(GIT_REFERENCE_NOT_FOUND_REGEX)
            tag = error.message.match(GIT_REFERENCE_NOT_FOUND_REGEX).named_captures.fetch("tag")
            # Unfortunately the error message doesn't include the package name.
            # TODO: Talk with pipenv maintainers about exposing the package name, it used to be part of the error output
            raise GitDependencyReferenceNotFound, "(unknown package at #{tag})"
          end

          if error.message.match?(GIT_DEPENDENCY_UNREACHABLE_REGEX)
            url = error.message.match(GIT_DEPENDENCY_UNREACHABLE_REGEX)
                       .named_captures.fetch("url")
            raise GitDependenciesNotReachable, url
          end

          if error.message.include?("Could not find a version") || error.message.include?("ResolutionFailure")
            check_original_requirements_resolvable
          end

          if error.message.include?("SyntaxError: invalid syntax")
            raise DependencyFileNotResolvable,
                  "SyntaxError while installing dependencies. Is one of the dependencies not Python 3 compatible? " \
                  "Pip v21 no longer supports Python 2."
          end

          if (error.message.include?('Command "python setup.py egg_info"') ||
              error.message.include?(
                "exit status 1: python setup.py egg_info"
              )) &&
             check_original_requirements_resolvable
            # The latest version of the dependency we're updating is borked
            # (because it has an unevaluatable setup.py). Skip the update.
            return
          end

          if error.message.include?("UnsupportedPythonVersion") &&
             language_version_manager.user_specified_python_version
            check_original_requirements_resolvable

            # The latest version of the dependency we're updating to needs a
            # different Python version. Skip the update.
            return if error.message.match?(/#{Regexp.quote(dependency.name)}/i)
          end

          raise unless error.message.include?("ResolutionFailure")
        end
        # rubocop:enable Metrics/CyclomaticComplexity
        # rubocop:enable Metrics/PerceivedComplexity
        # rubocop:enable Metrics/AbcSize
        # rubocop:enable Metrics/MethodLength

        # Needed because Pipenv's resolver isn't perfect.
        # Note: We raise errors from this method, rather than returning a
        # boolean, so that all deps for this repo will raise identical
        # errors when failing to update
        def check_original_requirements_resolvable
          SharedHelpers.in_a_temporary_repo_directory(base_directory, repo_contents_path) do
            write_temporary_dependency_files(update_pipfile: false)

            pipenv_runner.run_upgrade("==#{dependency.version}")

            true
          rescue SharedHelpers::HelperSubprocessFailed => e
            handle_pipenv_errors_resolving_original_reqs(e)
          end
        end

        def base_directory
          dependency_files.first.directory
        end

        def handle_pipenv_errors_resolving_original_reqs(error)
          if error.message.include?("Could not find a version") ||
             error.message.include?("package versions have conflicting dependencies")
            msg = clean_error_message(error.message)
            msg.gsub!(/\s+\(from .*$/, "")
            raise if msg.empty?

            raise DependencyFileNotResolvable, msg
          end

          if error.message.include?("UnsupportedPythonVersion") &&
             language_version_manager.user_specified_python_version
            msg = clean_error_message(error.message)
                  .lines.take_while { |l| !l.start_with?("File") }.join.strip
            raise if msg.empty?

            raise DependencyFileNotResolvable, msg
          end

          handle_pipenv_installation_error(error.message) if error.message.match?(PIPENV_INSTALLATION_ERROR_REGEX)

          # Raise an unhandled error, as this could be a problem with
          # Dependabot's infrastructure, rather than the Pipfile
          raise
        end

        def clean_error_message(message)
          # Pipenv outputs a lot of things to STDERR, so we need to clean
          # up the error message
          msg_lines = message.lines
          msg = msg_lines
                .take_while { |l| !l.start_with?("During handling of") }
                .drop_while do |l|
                  next false if l.start_with?("CRITICAL:")
                  next false if l.start_with?("ERROR:")
                  next false if l.start_with?("packaging.specifiers")
                  next false if l.start_with?("pipenv.patched.pip._internal")
                  next false if l.include?("Max retries exceeded")

                  true
                end.join.strip

          # We also need to redact any URLs, as they may include credentials
          msg.gsub(/http.*?(?=\s)/, "<redacted>")
        end

        def handle_pipenv_installation_error(error_message)
          # Find the dependency that's causing resolution to fail
          dependency_name = error_message.match(PIPENV_INSTALLATION_ERROR_REGEX).named_captures["name"]
          raise unless dependency_name

          msg = "Pipenv failed to install \"#{dependency_name}\". This could be caused by missing system " \
                "dependencies that can't be installed by Dependabot or required installation flags.\n\n" \
                "Error output from running \"pipenv lock\":\n" \
                "#{clean_error_message(error_message)}"

          raise DependencyFileNotResolvable, msg
        end

        def write_temporary_dependency_files(update_pipfile: true)
          dependency_files.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, file.content)
          end

          # Overwrite the .python-version with updated content
          File.write(".python-version", language_version_manager.python_major_minor)

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
          return unless update_pipfile

          # Overwrite the pipfile with updated content
          File.write(
            "Pipfile",
            pipfile_content
          )
        end

        def install_required_python
          # Initialize a git repo to appease pip-tools
          begin
            run_command("git init") if setup_files.any?
          rescue Dependabot::SharedHelpers::HelperSubprocessFailed
            nil
          end

          language_version_manager.install_required_python
        end

        def sanitized_setup_file_content(file)
          @sanitized_setup_file_content ||= {}
          @sanitized_setup_file_content[file.name] ||=
            Python::FileUpdater::SetupFileSanitizer
            .new(setup_file: file, setup_cfg: setup_cfg(file))
            .sanitized_content
        end

        def setup_cfg(file)
          config_name = file.name.sub(/\.py$/, ".cfg")
          dependency_files.find { |f| f.name == config_name }
        end

        def pipfile_content
          content = pipfile.content
          content = add_private_sources(content)
          content = update_python_requirement(content)
          content
        end

        def update_python_requirement(pipfile_content)
          Python::FileUpdater::PipfilePreparer
            .new(pipfile_content: pipfile_content)
            .update_python_requirement(language_version_manager.python_major_minor)
        end

        def add_private_sources(pipfile_content)
          Python::FileUpdater::PipfilePreparer
            .new(pipfile_content: pipfile_content)
            .replace_sources(credentials)
        end

        def run_command(command)
          SharedHelpers.run_shell_command(command, stderr_to_stdout: true)
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

        def pipenv_runner
          @pipenv_runner ||=
            PipenvRunner.new(
              dependency: dependency,
              lockfile: lockfile,
              language_version_manager: language_version_manager
            )
        end

        def pipfile
          dependency_files.find { |f| f.name == "Pipfile" }
        end

        def lockfile
          dependency_files.find { |f| f.name == "Pipfile.lock" }
        end

        def setup_files
          dependency_files.select { |f| f.name.end_with?("setup.py") }
        end

        def setup_cfg_files
          dependency_files.select { |f| f.name.end_with?("setup.cfg") }
        end
      end
    end
  end
end
