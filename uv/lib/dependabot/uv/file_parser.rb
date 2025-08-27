# typed: strict
# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/file_parsers/base/dependency_set"
require "dependabot/shared_helpers"
require "dependabot/uv/requirement"
require "dependabot/errors"
require "dependabot/uv/language"
require "dependabot/uv/native_helpers"
require "dependabot/uv/name_normaliser"
require "dependabot/uv/requirements_file_matcher"
require "dependabot/uv/language_version_manager"
require "dependabot/uv/package_manager"
require "toml-rb"

module Dependabot
  module Uv
    class FileParser < Dependabot::FileParsers::Base
      extend T::Sig
      require_relative "file_parser/pyproject_files_parser"
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
      # uv version from shell, we are ensuring that the actual update is not blocked
      # in any way if any metric collection exception start happening
      UNDETECTED_PACKAGE_MANAGER_VERSION = "0.0"

      sig { override.returns(T::Array[Dependency]) }
      def parse
        dependency_set = DependencySet.new

        dependency_set += pyproject_file_dependencies if pyproject
        dependency_set += uv_lock_file_dependencies
        dependency_set += requirement_dependencies if requirement_files.any?

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

      # Normalize dependency names to match the PyPI index normalization
      sig { params(name: String, extras: T::Array[String]).returns(String) }
      def self.normalize_dependency_name(name, extras = [])
        NameNormaliser.normalise_including_extras(name, extras)
      end

      private

      sig { returns(LanguageVersionManager) }
      def language_version_manager
        @language_version_manager ||= T.let(LanguageVersionManager.new(python_requirement_parser:
                                        python_requirement_parser), T.nilable(LanguageVersionManager))
      end

      sig { returns(FileParser::PythonRequirementParser) }
      def python_requirement_parser
        @python_requirement_parser ||= T.let(PythonRequirementParser.new(dependency_files:
                                         dependency_files), T.nilable(PythonRequirementParser))
      end

      sig { returns(Ecosystem::VersionManager) }
      def package_manager
        @package_manager ||= T.let(detected_package_manager, T.nilable(Ecosystem::VersionManager))
      end

      sig { returns(Ecosystem::VersionManager) }
      def detected_package_manager
        PackageManager.new(T.must(detect_uv_version))
      end

      sig { returns(T.nilable(String)) }
      def detect_uv_version
        version = uv_version.to_s.split("version ").last&.split(")")&.first

        log_if_version_malformed("uv", version)

        version if version&.match?(/^\d+(?:\.\d+)*$/)
      rescue StandardError
        nil
      end

      sig { returns(T.any(String, T.untyped)) }
      def uv_version
        version_info = SharedHelpers.run_shell_command("pyenv exec uv --version")
        Dependabot.logger.info("Package manager uv, Info : #{version_info}")

        version_info.match(/\d+(?:\.\d+)*/)&.to_s
      rescue StandardError => e
        Dependabot.logger.error(e.message)
        nil
      end

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
        if version.match?(/^\d+(?:\.\d+)*$/)
          true
        else
          Dependabot.logger.warn("Detected #{package_manager} with malformed version #{version}")
          false
        end
      end

      sig { returns(String) }
      def python_raw_version
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

      sig { returns(T::Array[DependencyFile]) }
      def requirement_files
        dependency_files.select { |f| f.name.end_with?(".txt", ".in") }
      end

      sig { returns(T::Array[DependencyFile]) }
      def uv_lock_files
        dependency_files.select { |f| f.name == "uv.lock" }
      end

      sig { returns(DependencySet) }
      def uv_lock_file_dependencies
        dependency_set = DependencySet.new

        uv_lock_files.each do |file|
          lockfile_content = TomlRB.parse(file.content)
          packages = lockfile_content.fetch("package", [])

          packages.each do |package_data|
            next unless package_data.is_a?(Hash) && package_data["name"] && package_data["version"]

            dependency_set << Dependency.new(
              name: normalised_name(package_data["name"]),
              version: package_data["version"],
              requirements: [], # Lock files don't contain requirements
              package_manager: "uv"
            )
          end
        rescue StandardError => e
          Dependabot.logger.warn("Error parsing uv.lock: #{e.message}")
        end

        dependency_set
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
          next if blocking_marker?(dep)

          name = dep["name"]
          file = dep["file"]
          version = dep["version"]
          original_file = get_original_file(file)

          requirements =
            if original_file && requirements_in_file_matcher.compiled_file?(original_file) then []
            else
              [{
                requirement: dep["requirement"],
                file: Pathname.new(file).cleanpath.to_path,
                source: nil,
                groups: group_from_filename(file)
              }]
            end

          # PyYAML < 6.0 will cause `pip-compile` to fail due to incompatibility with Cython 3. Workaround it. PR #8189
          SharedHelpers.run_shell_command("pyenv exec pip install cython<3.0") if old_pyyaml?(name, version)

          dependencies <<
            Dependency.new(
              name: normalised_name(name, dep["extras"]),
              version: version&.include?("*") ? nil : version,
              requirements: requirements,
              package_manager: "uv"
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
          Version.new(python_version) < Version.new(version)
        when "<="
          Version.new(python_version) <= Version.new(version)
        when ">"
          Version.new(python_version) > Version.new(version)
        when ">="
          Version.new(python_version) >= Version.new(version)
        when "=="
          Version.new(python_version) == Version.new(version)
        else
          false
        end
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

        raise DependencyFileNotEvaluatable, e.message
      end

      sig { params(requirements: T.untyped).returns(T.untyped) }
      def check_requirements(requirements)
        requirements.each do |dep|
          next unless dep["requirement"]

          Requirement.new(dep["requirement"].split(","))
        rescue Gem::Requirement::BadRequirementError => e
          raise DependencyFileNotEvaluatable, e.message
        end
      end

      sig { returns(T::Array[DependencyFile]) }
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
        FileParser.normalize_dependency_name(name, extras)
      end

      sig { override.returns(T.untyped) }
      def check_required_files
        filenames = dependency_files.map(&:name)
        return if filenames.any? { |name| name.end_with?(".txt", ".in") }
        return if pyproject

        raise "Missing required files!"
      end

      sig { returns(T.nilable(DependencyFile)) }
      def pyproject
        @pyproject ||= T.let(get_original_file("pyproject.toml"), T.nilable(DependencyFile))
      end

      sig { returns(T::Array[DependencyFile]) }
      def requirements_in_files
        @requirements_in_files ||= T.let(dependency_files.select { |f| f.name.end_with?(".in") }, T.untyped)
      end

      sig { returns(RequiremenstFileMatcher) }
      def requirements_in_file_matcher
        @requirements_in_file_matcher ||= T.let(RequiremenstFileMatcher.new(requirements_in_files),
                                                T.nilable(RequiremenstFileMatcher))
      end
    end
  end
end

Dependabot::FileParsers.register("uv", Dependabot::Uv::FileParser)
