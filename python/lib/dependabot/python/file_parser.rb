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

module Dependabot
  module Python
    class FileParser < Dependabot::FileParsers::Base
      require_relative "file_parser/pipfile_files_parser"
      require_relative "file_parser/poetry_files_parser"
      require_relative "file_parser/setup_file_parser"

      POETRY_DEPENDENCY_TYPES =
        %w(tool.poetry.dependencies tool.poetry.dev-dependencies).freeze
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
        InvalidRequirement ValueError
      ).freeze

      def parse
        dependency_set = DependencySet.new

        dependency_set += pipenv_dependencies if pipfile
        dependency_set += poetry_dependencies if using_poetry?
        dependency_set += requirement_dependencies if requirement_files.any?
        dependency_set += setup_file_dependencies if setup_file

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
          # This isn't ideal, but currently the FileUpdater won't update
          # deps that appear in a requirements.txt and Pipfile / Pipfile.lock
          # and *aren't* a straight lockfile for the Pipfile
          next if included_in_pipenv_deps?(normalised_name(dep["name"]))

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
                groups: []
              }]
            end

          dependencies <<
            Dependency.new(
              name: normalised_name(dep["name"]),
              version: dep["version"]&.include?("*") ? nil : dep["version"],
              requirements: requirements,
              package_manager: "pip"
            )
        end
        dependencies
      end

      def included_in_pipenv_deps?(dep_name)
        return false unless pipfile

        pipenv_dependencies.dependencies.map(&:name).include?(dep_name)
      end

      def blocking_marker?(dep)
        return false if dep["markers"].include?(">")
        return true if dep["markers"].include?("<")
        return true if dep["markers"].include?("==")

        false
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
      rescue SharedHelpers::HelperSubprocessFailed => error
        evaluation_errors = REQUIREMENT_FILE_EVALUATION_ERRORS
        raise unless error.message.start_with?(*evaluation_errors)

        raise Dependabot::DependencyFileNotEvaluatable, error.message
      end

      def check_requirements(requirements)
        requirements.each do |dep|
          next unless dep["requirement"]

          Python::Requirement.new(dep["requirement"].split(","))
        rescue Gem::Requirement::BadRequirementError => error
          raise Dependabot::DependencyFileNotEvaluatable, error.message
        end
      end

      def write_temporary_dependency_files
        dependency_files.
          reject { |f| f.name == ".python-version" }.
          each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, file.content)
          end
      end

      # See https://www.python.org/dev/peps/pep-0503/#normalized-names
      def normalised_name(name)
        name.downcase.gsub(/[-_.]+/, "-")
      end

      def check_required_files
        filenames = dependency_files.map(&:name)
        return if filenames.any? { |name| name.end_with?(".txt", ".in") }
        return if pipfile
        return if pyproject
        return if setup_file

        raise "No requirements.txt or setup.py!"
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

      def pip_compile_files
        @pip_compile_files ||=
          dependency_files.select { |f| f.name.end_with?(".in") }
      end
    end
  end
end

Dependabot::FileParsers.
  register("pip", Dependabot::Python::FileParser)
