# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
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
require "dependabot/python/authed_url_builder"
require "dependabot/python/name_normaliser"

module Dependabot
  module Python
    class UpdateChecker
      # This class does version resolution for pyproject.toml files.
      class PoetryVersionResolver
        extend T::Sig
        extend T::Helpers

        GIT_REFERENCE_NOT_FOUND_REGEX = /
          (Failed to checkout
          (?<tag>.+?)
          (?<url>.+?).git at '(?<tag>.+?)'
          |
          ...Failedtoclone
          (?<url>.+?).gitat'(?<tag>.+?)',
          verifyrefexistsonremote)
        /x
        GIT_DEPENDENCY_UNREACHABLE_REGEX = /
          \s+Failed\sto\sclone
          \s+(?<url>.+?),
          \s+check\syour\sgit\sconfiguration
        /mx

        INCOMPATIBLE_CONSTRAINTS = /Incompatible constraints in requirements of (?<dep>.+?) ((?<ver>.+?)):/

        PACKAGE_RESOLVER_ERRORS = T.let({
          package_info_error: /Unable to determine package info/,
          self_dep_error: /Package '(?<path>.*)' is listed as a dependency of itself./,
          incompatible_constraints: /Incompatible constraints in requirements/
        }.freeze, T::Hash[T.nilable(String), Regexp])

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(T.nilable(String)) }
        attr_reader :repo_contents_path

        sig { returns(Dependabot::Python::PoetryErrorHandler) }
        attr_reader :error_handler

        sig do
          params(
            dependency: Dependabot::Dependency,
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential],
            repo_contents_path: T.nilable(String)
          ).void
        end
        def initialize(dependency:, dependency_files:, credentials:, repo_contents_path:)
          @dependency               = T.let(dependency, Dependabot::Dependency)
          @dependency_files         = T.let(dependency_files, T::Array[Dependabot::DependencyFile])
          @credentials              = T.let(credentials, T::Array[Dependabot::Credential])
          @repo_contents_path       = T.let(repo_contents_path, T.nilable(String))
          @error_handler = T.let(PoetryErrorHandler.new(dependencies: dependency, dependency_files: dependency_files),
                                 Dependabot::Python::PoetryErrorHandler)
          @resolvable = T.let({}, T::Hash[Gem::Version, T::Boolean])
          @latest_resolvable_version_string = T.let({}, T::Hash[T.nilable(String), T.nilable(String)])
          @original_reqs_resolvable = T.let(nil, T.nilable(T::Boolean))
          @python_requirement_parser = T.let(nil, T.nilable(FileParser::PythonRequirementParser))
          @language_version_manager = T.let(nil, T.nilable(LanguageVersionManager))
        end

        sig { params(requirement: T.nilable(String)).returns(T.nilable(Dependabot::Python::Version)) }
        def latest_resolvable_version(requirement: nil)
          version_string =
            fetch_latest_resolvable_version_string(requirement: requirement)

          version_string.nil? ? nil : Python::Version.new(version_string)
        end

        sig { params(version: Gem::Version).returns(T::Boolean) }
        def resolvable?(version:)
          return T.must(@resolvable[version]) if @resolvable.key?(version)

          @resolvable[version] = if fetch_latest_resolvable_version_string(requirement: "==#{version}")
                                   true
                                 else
                                   false
                                 end
        rescue SharedHelpers::HelperSubprocessFailed => e
          raise unless e.message.include?("version solving failed.")

          @resolvable[version] = false
        end

        private

        sig { params(requirement: T.nilable(String)).returns(T.nilable(String)) }
        def fetch_latest_resolvable_version_string(requirement:)
          return @latest_resolvable_version_string[requirement] if @latest_resolvable_version_string.key?(requirement)

          @latest_resolvable_version_string[requirement] ||=
            SharedHelpers.in_a_temporary_directory do
              SharedHelpers.with_git_configured(credentials: credentials) do
                write_temporary_dependency_files(updated_req: requirement)
                add_auth_env_vars

                language_version_manager.install_required_python

                # use system git instead of the pure Python dulwich
                run_poetry_command("pyenv exec poetry config system-git-client true")

                # Shell out to Poetry, which handles everything for us.
                run_poetry_update_command

                updated_lockfile = File.read("poetry.lock")
                updated_lockfile = TomlRB.parse(updated_lockfile)

                fetch_version_from_parsed_lockfile(updated_lockfile)
              rescue SharedHelpers::HelperSubprocessFailed => e
                handle_poetry_errors(e)
              end
            end
        end

        sig { params(updated_lockfile: T::Hash[String, T.untyped]).returns(T.nilable(String)) }
        def fetch_version_from_parsed_lockfile(updated_lockfile)
          version =
            updated_lockfile.fetch("package", [])
                            .find { |d| d["name"] && normalise(d["name"]) == dependency.name }
                            &.fetch("version")

          return version unless version.nil? && dependency.top_level?

          raise "No version in lockfile!"
        end

        # rubocop:disable Metrics/AbcSize
        sig { params(error: StandardError).returns(T.nilable(String)) }
        def handle_poetry_errors(error)
          error_handler.handle_poetry_error(error)

          if error.message.gsub(/\s/, "").match?(GIT_REFERENCE_NOT_FOUND_REGEX)
            message = error.message.gsub(/\s/, "")
            match = message.match(GIT_REFERENCE_NOT_FOUND_REGEX)
            name = if (url = T.must(match).named_captures.fetch("url"))
                     File.basename(T.must(URI.parse(url).path))
                   else
                     T.must(message.match(GIT_REFERENCE_NOT_FOUND_REGEX))
                      .named_captures.fetch("name")
                   end
            raise GitDependencyReferenceNotFound, T.must(name)
          end

          if error.message.match?(GIT_DEPENDENCY_UNREACHABLE_REGEX)
            url = T.must(error.message.match(GIT_DEPENDENCY_UNREACHABLE_REGEX))
                   .named_captures.fetch("url")
            raise GitDependenciesNotReachable, T.must(url)
          end

          raise unless error.message.include?("SolverProblemError") ||
                       error.message.include?("not found") ||
                       error.message.include?("version solving failed.")

          check_original_requirements_resolvable

          # If the original requirements are resolvable but the new version
          # would break Python version compatibility the update is blocked
          return if error.message.include?("support the following Python")

          # If any kind of other error is now occurring as a result of our
          # change then we want to hear about it
          raise
        end
        # rubocop:enable Metrics/AbcSize

        # Using `--lock` avoids doing an install.
        # Using `--no-interaction` avoids asking for passwords.
        sig { void }
        def run_poetry_update_command
          run_poetry_command(
            "pyenv exec poetry update #{dependency.name} --lock --no-interaction",
            fingerprint: "pyenv exec poetry update <dependency_name> --lock --no-interaction"
          )
        end

        sig { returns(T::Boolean) }
        def check_original_requirements_resolvable
          return @original_reqs_resolvable if @original_reqs_resolvable

          SharedHelpers.in_a_temporary_directory do
            write_temporary_dependency_files(update_pyproject: false)

            run_poetry_update_command

            @original_reqs_resolvable = true
          rescue SharedHelpers::HelperSubprocessFailed => e
            raise unless e.message.include?("SolverProblemError") ||
                         e.message.include?("not found") ||
                         e.message.include?("version solving failed.")

            msg = clean_error_message(e.message)
            raise DependencyFileNotResolvable, msg
          end
        end

        sig { params(message: String).returns(String) }
        def clean_error_message(message)
          # Redact any URLs, as they may include credentials
          message.gsub(/http.*?(?=\s)/, "<redacted>")
        end

        sig do
          params(
            updated_req: T.nilable(String),
            update_pyproject: T::Boolean
          ).void
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

        sig { void }
        def add_auth_env_vars
          Python::FileUpdater::PyprojectPreparer
            .new(pyproject_content: T.must(T.must(pyproject).content))
            .add_auth_env_vars(credentials)
        end

        sig { params(updated_requirement: T.nilable(String)).returns(String) }
        def updated_pyproject_content(updated_requirement:)
          content = T.must(T.must(pyproject).content)
          content = sanitize_pyproject_content(content)
          content = update_python_requirement(content)
          content = freeze_other_dependencies(content)
          content = set_target_dependency_req(content, updated_requirement)
          content
        end

        sig { returns(String) }
        def sanitized_pyproject_content
          content = T.must(T.must(pyproject).content)
          content = sanitize_pyproject_content(content)
          content = update_python_requirement(content)
          content
        end

        sig { params(pyproject_content: String).returns(String) }
        def sanitize_pyproject_content(pyproject_content)
          Python::FileUpdater::PyprojectPreparer
            .new(pyproject_content: pyproject_content)
            .sanitize
        end

        sig { params(pyproject_content: String).returns(String) }
        def update_python_requirement(pyproject_content)
          Python::FileUpdater::PyprojectPreparer
            .new(pyproject_content: pyproject_content)
            .update_python_requirement(language_version_manager.python_version)
        end

        sig { params(pyproject_content: String).returns(String) }
        def freeze_other_dependencies(pyproject_content)
          Python::FileUpdater::PyprojectPreparer
            .new(pyproject_content: pyproject_content, lockfile: lockfile)
            .freeze_top_level_dependencies_except([dependency])
        end

        sig { params(pyproject_content: String, updated_requirement: T.nilable(String)).returns(String) }
        def set_target_dependency_req(pyproject_content, updated_requirement)
          return pyproject_content unless updated_requirement

          pyproject_object = TomlRB.parse(pyproject_content)
          poetry_object = pyproject_object.dig("tool", "poetry")

          Dependabot::Python::FileParser::PyprojectFilesParser::POETRY_DEPENDENCY_TYPES.each do |type|
            dependencies = poetry_object[type]
            next unless dependencies

            update_dependency_requirement(dependencies, updated_requirement)
          end

          groups = poetry_object["group"]&.values || []
          groups.each do |group_spec|
            update_dependency_requirement(group_spec["dependencies"], updated_requirement)
          end

          # If this is a sub-dependency, add the new requirement
          unless dependency.requirements.find { |r| r[:file] == T.must(pyproject).name }
            poetry_object[subdep_type] ||= {}
            poetry_object[subdep_type][dependency.name] = updated_requirement
          end

          TomlRB.dump(pyproject_object)
        end

        sig { params(toml_node: T::Hash[String, T.untyped], requirement: String).void }
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

        sig { returns(String) }
        def subdep_type
          dependency.production? ? "dependencies" : "dev-dependencies"
        end

        sig { returns(FileParser::PythonRequirementParser) }
        def python_requirement_parser
          @python_requirement_parser ||=
            FileParser::PythonRequirementParser.new(
              dependency_files: dependency_files
            )
        end

        sig { returns(LanguageVersionManager) }
        def language_version_manager
          @language_version_manager ||=
            LanguageVersionManager.new(
              python_requirement_parser: python_requirement_parser
            )
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def pyproject
          dependency_files.find { |f| f.name == "pyproject.toml" }
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def poetry_lock
          dependency_files.find { |f| f.name == "poetry.lock" }
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def lockfile
          poetry_lock
        end

        sig { params(command: String, fingerprint: T.nilable(String)).returns(String) }
        def run_poetry_command(command, fingerprint: nil)
          SharedHelpers.run_shell_command(command, fingerprint: fingerprint)
        end

        sig { params(name: String).returns(String) }
        def normalise(name)
          NameNormaliser.normalise(name)
        end
      end
    end

    class PoetryErrorHandler < UpdateChecker
      extend T::Sig

      # if a valid config value is not found in project.toml file
      INVALID_CONFIGURATION = /The Poetry configuration is invalid:(?<config>.*)/

      # if .toml has incorrect version specification i.e. <0.2.0app
      INVALID_VERSION = /Could not parse version constraint: (?<ver>.*)/

      # dependency source link not accessible
      INVALID_LINK = /No valid distribution links found for package: "(?<dep>.*)" version: "(?<ver>.*)"/

      # Python version range mentioned in .toml [tool.poetry.dependencies] python = "x.x" is not satisfied by dependency
      PYTHON_RANGE_NOT_SATISFIED = /(?<dep>.*) requires Python (?<req_ver>.*), so it will not be satisfied for Python (?<men_ver>.*)/ # rubocop:disable Layout/LineLength

      # package version mentioned in .toml not found in package index
      PACKAGE_NOT_FOUND = /Package (?<pkg>.*) ((?<req_ver>.*)) not found./

      # client access error codes while accessing package index
      CLIENT_ERROR_CODES = T.let({
        error401: /401 Client Error/,
        error403: /403 Client Error/,
        error404: /404 Client Error/,
        http403: /HTTP error 403/,
        http404: /HTTP error 404/
      }.freeze, T::Hash[T.nilable(String), Regexp])

      # server response error codes while accessing package index
      SERVER_ERROR_CODES = T.let({
        server500: /500 Server Error/,
        server502: /502 Server Error/,
        server503: /503 Server Error/,
        server504: /504 Server Error/
      }.freeze, T::Hash[T.nilable(String), Regexp])

      # invalid configuration in pyproject.toml
      POETRY_VIRTUAL_ENV_CONFIG = %r{pypoetry/virtualenvs(.|\n)*list index out of range}

      # error related to local project as dependency in pyproject.toml
      ERR_LOCAL_PROJECT_PATH = /Path (?<path>.*) for (?<dep>.*) does not exist/

      TIME_OUT_ERRORS = T.let({
        time_out_max_retries: /Max retries exceeded/,
        time_out_read_timed_out: /Read timed out/,
        time_out_inactivity: /Timed out due to inactivity/
      }.freeze, T::Hash[T.nilable(String), Regexp])

      PACKAGE_RESOLVER_ERRORS = T.let({
        package_info_error: /Unable to determine package info/,
        self_dep_error: /Package '(?<path>.*)' is listed as a dependency of itself./,
        incompatible_constraints: /Incompatible constraints in requirements/
      }.freeze, T::Hash[T.nilable(String), Regexp])

      sig do
        params(
          dependencies: Dependabot::Dependency,
          dependency_files: T::Array[Dependabot::DependencyFile]
        ).void
      end
      def initialize(dependencies:, dependency_files:)
        @dependencies = T.let(dependencies, Dependabot::Dependency)
        @dependency_files = T.let(dependency_files, T::Array[Dependabot::DependencyFile])
      end

      private

      sig { returns(Dependabot::Dependency) }
      attr_reader :dependencies

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      attr_reader :dependency_files

      sig do
        params(
          url: T.nilable(String)
        ).returns(String)
      end
      def sanitize_url(url)
        T.must(url&.match(%r{^(?:https?://)?(?:[^@\n])?([^:/\n?]+)})).to_s
      end

      public

      # rubocop:disable Metrics/AbcSize
      # rubocop:disable Metrics/PerceivedComplexity
      # rubocop:disable Metrics/CyclomaticComplexity
      sig { params(error: Exception).void }
      def handle_poetry_error(error)
        Dependabot.logger.warn(error.message)

        if (msg = error.message.match(PoetryVersionResolver::INCOMPATIBLE_CONSTRAINTS) ||
            error.message.match(INVALID_CONFIGURATION) || error.message.match(INVALID_VERSION) ||
            error.message.match(INVALID_LINK))

          raise DependencyFileNotResolvable, msg
        end

        if (msg = error.message.match(PACKAGE_NOT_FOUND))
          raise DependencyFileNotResolvable, msg
        end

        raise DependencyFileNotResolvable, error.message if error.message.match(PYTHON_RANGE_NOT_SATISFIED)

        if error.message.match(POETRY_VIRTUAL_ENV_CONFIG) || error.message.match(ERR_LOCAL_PROJECT_PATH)
          msg = "Error while resolving pyproject.toml file"

          raise DependencyFileNotResolvable, msg
        end

        SERVER_ERROR_CODES.each do |(_error_codes, error_regex)|
          next unless error.message.match?(error_regex)

          index_url = URI.extract(error.message.to_s).last .then { sanitize_url(_1) }
          raise InconsistentRegistryResponse, index_url
        end

        TIME_OUT_ERRORS.each do |(_error_codes, error_regex)|
          next unless error.message.match?(error_regex)

          raise InconsistentRegistryResponse, "Inconsistent registry response"
        end

        CLIENT_ERROR_CODES.each do |(_error_codes, error_regex)|
          next unless error.message.match?(error_regex)

          index_url = URI.extract(error.message.to_s).last .then { sanitize_url(_1) }
          raise PrivateSourceAuthenticationFailure, index_url
        end

        PACKAGE_RESOLVER_ERRORS.each do |(_error_codes, error_regex)|
          next unless error.message.match?(error_regex)

          message = "Package solving failed while resolving manifest file"
          raise DependencyFileNotResolvable, message
        end
      end
      # rubocop:enable Metrics/AbcSize
      # rubocop:enable Metrics/PerceivedComplexity
      # rubocop:enable Metrics/CyclomaticComplexity
    end
  end
end
