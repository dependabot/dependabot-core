# frozen_string_literal: true

require "toml-rb"
require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/file_parsers/base/dependency_set"
require "dependabot/shared_helpers"
require "dependabot/python/requirement"
require "dependabot/errors"
require "dependabot/python/native_helpers"
require "dependabot/python/name_normaliser"

module Dependabot
  module Python
    class FileParser < Dependabot::FileParsers::Base
      require_relative "file_parser/pipfile_files_parser"
      require_relative "file_parser/poetry_files_parser"
      require_relative "file_parser/setup_file_parser"

      DEPENDENCY_GROUP_KEYS = [
        {
          pipfile: "packages",
          lockfile: "default"
        },
        {
          pipfile: "dev-packages",
          lockfile: "develop"
        }
      ].freeze
      REQUIREMENT_FILE_EVALUATION_ERRORS = %w(
        InstallationError RequirementsFileParseError InvalidMarker
        InvalidRequirement ValueError RecursionError
      ).freeze

      def parse
        # TODO: setup.py from external dependencies is evaluated. Provide guards before removing this.
        raise Dependabot::UnexpectedExternalCode if @reject_external_code

        dependency_set = DependencySet.new

        dependency_set += pipenv_dependencies if pipfile
        dependency_set += poetry_dependencies if using_poetry?
        dependency_set += requirement_dependencies if requirement_files.any?
        dependency_set += setup_file_dependencies if setup_file || setup_cfg_file

        dependency_set.dependencies
      end

      private

      def requirement_files
        dependency_files.select { |f| f.name.end_with?(".txt", ".in") }
      end

      def pipenv_dependencies
        @pipenv_dependencies ||=
          PipfileFilesParser.
          new(dependency_files: dependency_files).
          dependency_set
      end

      def poetry_dependencies
        @poetry_dependencies ||=
          PoetryFilesParser.
          new(dependency_files: dependency_files).
          dependency_set
      end

      def requirement_dependencies
        dependencies = DependencySet.new
        parsed_requirement_files.each do |dep|
          # If a requirement has a `<`, `<=` or '==' marker then updating it is
          # probably blocked. Ignore it.
          next if blocking_marker?(dep)

          requirements =
            if lockfile_for_pip_compile_file?(dep["file"]) then []
            else
              [{
                requirement: dep["requirement"],
                file: Pathname.new(dep["file"]).cleanpath.to_path,
                source: nil,
                groups: group_from_filename(dep["file"])
              }]
            end

          dependencies <<
            Dependency.new(
              name: normalised_name(dep["name"], dep["extras"]),
              version: dep["version"]&.include?("*") ? nil : dep["version"],
              requirements: requirements,
              package_manager: "pip"
            )
        end
        dependencies
      end

      def group_from_filename(filename)
        if filename.include?("dev") then ["dev-dependencies"]
        else
          ["dependencies"]
        end
      end

      def blocking_marker?(dep)
        return false if dep["markers"] == "None"
        return true if dep["markers"].include?("<")
        return false if dep["markers"].include?(">")

        dep["requirement"]&.include?("<")
      end

      def setup_file_dependencies
        @setup_file_dependencies ||=
          SetupFileParser.
          new(dependency_files: dependency_files).
          dependency_set
      end

      def lockfile_for_pip_compile_file?(filename)
        return false unless pip_compile_files.any?
        return false unless filename.end_with?(".txt")

        file = dependency_files.find { |f| f.name == filename }
        return true if file&.content&.match?(output_file_regex(filename))

        basename = filename.gsub(/\.txt$/, "")
        pip_compile_files.any? { |f| f.name == basename + ".in" }
      end

      def parsed_requirement_files
        SharedHelpers.in_a_temporary_directory do
          write_temporary_dependency_files

          requirements = SharedHelpers.run_helper_subprocess(
            command: "pyenv exec python #{NativeHelpers.python_helper_path}",
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

      def check_requirements(requirements)
        requirements.each do |dep|
          next unless dep["requirement"]

          Python::Requirement.new(dep["requirement"].split(","))
        rescue Gem::Requirement::BadRequirementError => e
          raise Dependabot::DependencyFileNotEvaluatable, e.message
        end
      end

      def write_temporary_dependency_files
        dependency_files.
          reject { |f| f.name == ".python-version" }.
          each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, remove_imports(file))
          end
      end

      def remove_imports(file)
        return file.content if file.path.end_with?(".tar.gz", ".whl", ".zip")

        file.content.lines.
          reject { |l| l.match?(/^['"]?(?<path>\..*?)(?=\[|#|'|"|$)/) }.
          reject { |l| l.match?(/^(?:-e)\s+['"]?(?<path>.*?)(?=\[|#|'|"|$)/) }.
          join
      end

      def normalised_name(name, extras = [])
        NameNormaliser.normalise_including_extras(name, extras)
      end

      def check_required_files
        filenames = dependency_files.map(&:name)
        return if filenames.any? { |name| name.end_with?(".txt", ".in") }
        return if pipfile
        return if pyproject
        return if setup_file
        return if setup_cfg_file

        raise "Missing required files!"
      end

      def pipfile
        @pipfile ||= get_original_file("Pipfile")
      end

      def pipfile_lock
        @pipfile_lock ||= get_original_file("Pipfile.lock")
      end

      def using_poetry?
        return false unless pyproject
        return true if poetry_lock || pyproject_lock

        !TomlRB.parse(pyproject.content).dig("tool", "poetry").nil?
      rescue TomlRB::ParseError, TomlRB::ValueOverwriteError
        raise Dependabot::DependencyFileNotParseable, pyproject.path
      end

      def output_file_regex(filename)
        "--output-file[=\s]+#{Regexp.escape(filename)}(?:\s|$)"
      end

      def pyproject
        @pyproject ||= get_original_file("pyproject.toml")
      end

      def pyproject_lock
        @pyproject_lock ||= get_original_file("pyproject.lock")
      end

      def poetry_lock
        @poetry_lock ||= get_original_file("poetry.lock")
      end

      def setup_file
        @setup_file ||= get_original_file("setup.py")
      end

      def setup_cfg_file
        @setup_cfg_file ||= get_original_file("setup.cfg")
      end

      def pip_compile_files
        @pip_compile_files ||=
          dependency_files.select { |f| f.name.end_with?(".in") }
      end
    end
  end
end

Dependabot::FileParsers.register("pip", Dependabot::Python::FileParser)
