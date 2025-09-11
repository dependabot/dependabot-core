# typed: strict
# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/file_parsers/base/dependency_set"
require "dependabot/shared_helpers"
require "dependabot/python/requirement"
require "dependabot/errors"
require "dependabot/python/language"
require "dependabot/python/native_helpers"
require "dependabot/python/name_normaliser"
require "dependabot/python/pip_compile_file_matcher"
require "dependabot/python/language_version_manager"
require "dependabot/python/package_manager"

module Dependabot
  module Python
    class FileParser < Dependabot::FileParsers::Base # rubocop:disable Metrics/ClassLength
      extend T::Sig

      require_relative "file_parser/pipfile_files_parser"
      require_relative "file_parser/pyproject_files_parser"
      require_relative "file_parser/setup_file_parser"
      require_relative "file_parser/python_requirement_parser"

      DEPENDENCY_GROUP_KEYS = T.let([
        {
          pipfile: "packages",
          lockfile: "default"
        },
        {
          pipfile: "dev-packages",
          lockfile: "develop"
        }
      ].freeze, T::Array[T::Hash[Symbol, String]])
      REQUIREMENT_FILE_EVALUATION_ERRORS = %w(
        InstallationError RequirementsFileParseError InvalidMarker
        InvalidRequirement ValueError RecursionError
      ).freeze

      # we use this placeholder version in case we are not able to detect any
      # PIP version from shell, we are ensuring that the actual update is not blocked
      # in any way if any metric collection exception start happening
      UNDETECTED_PACKAGE_MANAGER_VERSION = "0.0"

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        # TODO: setup.py from external dependencies is evaluated. Provide guards before removing this.
        raise Dependabot::UnexpectedExternalCode if @reject_external_code

        dependency_set = DependencySet.new

        dependency_set += pipenv_dependencies if pipfile
        dependency_set += pyproject_file_dependencies if pyproject
        dependency_set += requirement_dependencies if requirement_files.any?
        dependency_set += setup_file_dependencies if setup_file || setup_cfg_file

        dependency_set.dependencies
      end

      sig { override.returns(Ecosystem) }
      def ecosystem
        @ecosystem ||= T.let(
          Ecosystem.new(
            name: ECOSYSTEM,
            package_manager: package_manager,
            language: language
          ),
          T.nilable(Ecosystem)
        )
      end

      private

      sig { returns(Dependabot::Python::LanguageVersionManager) }
      def language_version_manager
        @language_version_manager ||= T.let(LanguageVersionManager.new(python_requirement_parser:
                                        python_requirement_parser), T.nilable(LanguageVersionManager))
      end

      sig { returns(Dependabot::Python::FileParser::PythonRequirementParser) }
      def python_requirement_parser
        @python_requirement_parser ||= T.let(FileParser::PythonRequirementParser.new(dependency_files:
                                         dependency_files), T.nilable(FileParser::PythonRequirementParser))
      end

      sig { returns(Ecosystem::VersionManager) }
      def package_manager
        if Dependabot::Experiments.enabled?(:enable_file_parser_python_local)
          Dependabot.logger.info("Detected package manager : #{detected_package_manager.name}")
        end

        @package_manager ||= T.let(detected_package_manager, T.nilable(Dependabot::Ecosystem::VersionManager))
      end

      sig { returns(Ecosystem::VersionManager) }
      def detected_package_manager
        setup_python_environment if Dependabot::Experiments.enabled?(:enable_file_parser_python_local)

        return PipenvPackageManager.new(T.must(detect_pipenv_version)) if detect_pipenv_version

        return PoetryPackageManager.new(T.must(detect_poetry_version)) if detect_poetry_version

        return PipCompilePackageManager.new(T.must(detect_pipcompile_version)) if detect_pipcompile_version

        PipPackageManager.new(detect_pip_version)
      end

      # Detects the version of poetry. If the version cannot be detected, it returns nil
      sig { returns(T.nilable(String)) }
      def detect_poetry_version
        if poetry_files
          package_manager = PoetryPackageManager::NAME

          version = package_manager_version(package_manager)
                    .to_s.split("version ").last&.split(")")&.first

          log_if_version_malformed(package_manager, version)

          # makes sure we have correct version format returned
          version if version&.match?(/^\d+(?:\.\d+)*$/)
        end
      rescue StandardError
        nil
      end

      # Detects the version of pip-compile. If the version cannot be detected, it returns nil
      sig { returns(T.nilable(String)) }
      def detect_pipcompile_version
        if pipcompile_in_file
          package_manager = PipCompilePackageManager::NAME

          version = package_manager_version(package_manager)
                    .to_s.split("version ").last&.split(")")&.first

          log_if_version_malformed(package_manager, version)

          # makes sure we have correct version format returned
          version if version&.match?(/^\d+(?:\.\d+)*$/)
        end
      rescue StandardError
        nil
      end

      # Detects the version of pipenv. If the version cannot be detected, it returns nil
      sig { returns(T.nilable(String)) }
      def detect_pipenv_version
        if pipenv_files
          package_manager = PipenvPackageManager::NAME

          version = package_manager_version(package_manager)
                    .to_s.split("version ").last&.strip

          log_if_version_malformed(package_manager, version)

          # makes sure we have correct version format returned
          version if version&.match?(/^\d+(?:\.\d+)*$/)
        end
      rescue StandardError
        nil
      end

      # Detects the version of pip. If the version cannot be detected, it returns 0.0
      sig { returns(String) }
      def detect_pip_version
        package_manager = PipPackageManager::NAME

        version = package_manager_version(package_manager)
                  .split("from").first&.split("pip")&.last&.strip

        log_if_version_malformed(package_manager, version)

        version&.match?(/^\d+(?:\.\d+)*$/) ? version : UNDETECTED_PACKAGE_MANAGER_VERSION
      rescue StandardError
        nil
      end

      sig { params(package_manager: String).returns(T.any(String, T.untyped)) }
      def package_manager_version(package_manager)
        version_info = SharedHelpers.run_shell_command("pyenv exec #{package_manager} --version")
        Dependabot.logger.info("Package manager #{package_manager}, Info : #{version_info}")

        version_info
      rescue StandardError => e
        Dependabot.logger.error(e.message)
        nil
      end

      # setup python local setup on file parser stage
      sig { returns(T.nilable(String)) }
      def setup_python_environment
        language_version_manager.install_required_python

        SharedHelpers.run_shell_command("pyenv local #{language_version_manager.python_major_minor}")
      rescue StandardError => e
        Dependabot.logger.error(e.message)
        nil
      end

      sig { params(package_manager: String, version: String).returns(T::Boolean) }
      def log_if_version_malformed(package_manager, version)
        # logs warning if malformed version is found
        if version.match?(/^\d+(?:\.\d+)*$/)
          true
        else
          Dependabot.logger.warn("Detected #{package_manager} with malformed version #{version}")
          false
        end
      end

      sig { returns(String) }
      def python_raw_version
        if Dependabot::Experiments.enabled?(:enable_file_parser_python_local)
          Dependabot.logger.info("Detected python version: #{language_version_manager.python_version}")
          Dependabot.logger.info("Detected python major minor version: #{language_version_manager.python_major_minor}")
        end

        language_version_manager.python_version
      end

      sig { returns(String) }
      def python_command_version
        language_version_manager.installed_version
      end

      sig { returns(T.nilable(Ecosystem::VersionManager)) }
      def language
        Language.new(
          detected_version: python_raw_version,
          raw_version: python_command_version
        )
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def requirement_files
        dependency_files.select { |f| f.name.end_with?(".txt", ".in") }
      end

      sig { returns(DependencySet) }
      def pipenv_dependencies
        @pipenv_dependencies ||= T.let(PipfileFilesParser.new(dependency_files:
                                    dependency_files).dependency_set, T.nilable(DependencySet))
      end

      sig { returns(DependencySet) }
      def pyproject_file_dependencies
        @pyproject_file_dependencies ||= T.let(PyprojectFilesParser.new(dependency_files:
                                          dependency_files).dependency_set, T.nilable(DependencySet))
      end

      sig { returns(DependencySet) }
      def requirement_dependencies
        dependencies = DependencySet.new
        parsed_requirement_files.each do |dep|
          # If a requirement has a `<`, `<=` or '==' marker then updating it is
          # probably blocked. Ignore it.
          next if blocking_marker?(dep)

          name = dep["name"]
          file = dep["file"]
          version = dep["version"]
          original_file = get_original_file(file)

          requirements =
            if original_file && pip_compile_file_matcher.lockfile_for_pip_compile_file?(original_file) then []
            else
              [{
                requirement: dep["requirement"],
                file: Pathname.new(file).cleanpath.to_path,
                source: nil,
                groups: group_from_filename(file)
              }]
            end

          # PyYAML < 6.0 will cause `pip-compile` to fail due to incompatibility with Cython 3. Workaround it.
          SharedHelpers.run_shell_command("pyenv exec pip install cython<3.0") if old_pyyaml?(name, version)

          dependencies <<
            Dependency.new(
              name: normalised_name(name, dep["extras"]),
              version: version&.include?("*") ? nil : version,
              requirements: requirements,
              package_manager: "pip"
            )
        end
        dependencies
      end

      sig { params(name: T.nilable(String), version: T.nilable(String)).returns(T::Boolean) }
      def old_pyyaml?(name, version)
        major_version = version&.split(".")&.first
        return false unless major_version

        name == "pyyaml" && major_version < "6"
      end

      sig { params(filename: String).returns(T::Array[String]) }
      def group_from_filename(filename)
        if filename.include?("dev") then ["dev-dependencies"]
        else
          ["dependencies"]
        end
      end

      sig { params(dep: T.untyped).returns(T::Boolean) }
      def blocking_marker?(dep)
        return false if dep["markers"] == "None"

        marker = dep["markers"]
        version = python_raw_version

        if marker.include?("python_version")
          !marker_satisfied?(marker, version)
        else
          return true if dep["markers"].include?("<")
          return false if dep["markers"].include?(">")
          return false if dep["requirement"].nil?

          dep["requirement"].include?("<")
        end
      end

      sig do
        params(marker: T.untyped, python_version: T.any(String, Integer, Gem::Version)).returns(T::Boolean)
      end
      def marker_satisfied?(marker, python_version)
        conditions = marker.split(/\s+(and|or)\s+/)

        # Explicitly define the type of result as T::Boolean
        result = T.let(evaluate_condition(conditions.shift, python_version), T::Boolean)

        until conditions.empty?
          operator = conditions.shift
          next_condition = conditions.shift
          next_result = evaluate_condition(next_condition, python_version)

          result = if operator == "and"
                     result && next_result
                   else
                     result || next_result
                   end
        end

        result
      end

      sig do
        params(condition: T.untyped,
               python_version: T.any(String, Integer, Gem::Version)).returns(T::Boolean)
      end
      def evaluate_condition(condition, python_version)
        operator, version = condition.match(/([<>=!]=?)\s*"?([\d.]+)"?/)&.captures

        case operator
        when "<"
          Dependabot::Python::Version.new(python_version) < Dependabot::Python::Version.new(version)
        when "<="
          Dependabot::Python::Version.new(python_version) <= Dependabot::Python::Version.new(version)
        when ">"
          Dependabot::Python::Version.new(python_version) > Dependabot::Python::Version.new(version)
        when ">="
          Dependabot::Python::Version.new(python_version) >= Dependabot::Python::Version.new(version)
        when "=="
          Dependabot::Python::Version.new(python_version) == Dependabot::Python::Version.new(version)
        else
          false
        end
      end

      sig { returns(DependencySet) }
      def setup_file_dependencies
        @setup_file_dependencies ||= T.let(SetupFileParser.new(dependency_files: dependency_files)
                                    .dependency_set, T.nilable(DependencySet))
      end

      sig { returns(T.untyped) }
      def parsed_requirement_files
        SharedHelpers.in_a_temporary_directory do
          write_temporary_dependency_files

          requirements = SharedHelpers.run_helper_subprocess(
            command: "pyenv exec python3 #{NativeHelpers.python_helper_path}",
            function: "parse_requirements",
            args: [Dir.pwd]
          )

          check_requirements(requirements)
          requirements
        end
      rescue SharedHelpers::HelperSubprocessFailed => e
        evaluation_errors = REQUIREMENT_FILE_EVALUATION_ERRORS
        raise unless e.message.start_with?(*evaluation_errors)

        raise Dependabot::DependencyFileNotEvaluatable, e.message
      end

      sig { params(requirements: T.untyped).returns(T.untyped) }
      def check_requirements(requirements)
        requirements.each do |dep|
          next unless dep["requirement"]

          Python::Requirement.new(dep["requirement"].split(","))
        rescue Gem::Requirement::BadRequirementError => e
          raise Dependabot::DependencyFileNotEvaluatable, e.message
        end
      end

      sig { returns(T::Boolean) }
      def pipcompile_in_file
        requirement_files.any? { |f| f.name.end_with?(PipCompilePackageManager::MANIFEST_FILENAME) }
      end

      sig { returns(T::Boolean) }
      def pipenv_files
        dependency_files.any? { |f| f.name == PipenvPackageManager::LOCKFILE_FILENAME }
      end

      sig { returns(T.nilable(TrueClass)) }
      def poetry_files
        true if get_original_file(PoetryPackageManager::LOCKFILE_NAME)
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def write_temporary_dependency_files
        dependency_files
          .reject { |f| f.name == ".python-version" }
          .each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, remove_imports(file))
          end
      end

      sig { params(file: T.untyped).returns(T.untyped) }
      def remove_imports(file)
        return file.content if file.path.end_with?(".tar.gz", ".whl", ".zip")

        file.content.lines
            .reject { |l| l.match?(/^['"]?(?<path>\..*?)(?=\[|#|'|"|$)/) }
            .reject { |l| l.match?(/^(?:-e)\s+['"]?(?<path>.*?)(?=\[|#|'|"|$)/) }
            .join
      end

      sig { params(name: String, extras: T::Array[String]).returns(String) }
      def normalised_name(name, extras = [])
        NameNormaliser.normalise_including_extras(name, extras)
      end

      sig { override.returns(T.untyped) }
      def check_required_files
        filenames = dependency_files.map(&:name)
        return if filenames.any? { |name| name.end_with?(".txt", ".in") }
        return if pipfile
        return if pyproject
        return if setup_file
        return if setup_cfg_file

        raise "Missing required files!"
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def pipfile
        @pipfile ||= T.let(get_original_file("Pipfile"), T.nilable(Dependabot::DependencyFile))
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def pipfile_lock
        @pipfile_lock ||= T.let(get_original_file("Pipfile.lock"), T.nilable(Dependabot::DependencyFile))
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def pyproject
        @pyproject ||= T.let(get_original_file("pyproject.toml"), T.nilable(Dependabot::DependencyFile))
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def poetry_lock
        @poetry_lock ||= T.let(get_original_file("poetry.lock"), T.nilable(Dependabot::DependencyFile))
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def setup_file
        @setup_file ||= T.let(get_original_file("setup.py"), T.nilable(Dependabot::DependencyFile))
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def setup_cfg_file
        @setup_cfg_file ||= T.let(get_original_file("setup.cfg"), T.nilable(Dependabot::DependencyFile))
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def pip_compile_files
        @pip_compile_files ||= T.let(dependency_files.select { |f| f.name.end_with?(".in") }, T.untyped)
      end

      sig { returns(Dependabot::Python::PipCompileFileMatcher) }
      def pip_compile_file_matcher
        @pip_compile_file_matcher ||= T.let(PipCompileFileMatcher.new(pip_compile_files),
                                            T.nilable(Dependabot::Python::PipCompileFileMatcher))
      end
    end
  end
end

Dependabot::FileParsers.register("pip", Dependabot::Python::FileParser)
