# frozen_string_literal: true

require "toml-rb"

require "dependabot/dependency"
require "dependabot/file_parsers/base"
require "dependabot/file_parsers/base/dependency_set"
require "dependabot/shared_helpers"
require "dependabot/utils/python/requirement"
require "dependabot/errors"

module Dependabot
  module FileParsers
    module Python
      class Pip < Dependabot::FileParsers::Base
        require_relative "pip/pipfile_files_parser"
        require_relative "pip/poetry_files_parser"

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

        def parse
          dependency_set = DependencySet.new

          # Currently, we assume users will only be using one dependency
          # management tool - Pipenv, Poetry, or pip-tools / requirements.txt.
          # In future it would be nice to handle setups that use multiple
          # managers at once (e.g., where a requirements.txt is generated from
          # Pipfile.lock).
          case parser_type
          when :pipfile
            dependency_set += pipfile_files_parser.dependency_set
          when :poetry
            dependency_set += poetry_files_parser.dependency_set
          when :requirements_and_pip_compile
            dependency_set += requirement_dependencies
          else raise "Unexpected parser type: #{parser_type}"
          end

          dependency_set += setup_file_dependencies if setup_file
          dependency_set.dependencies
        end

        private

        def parser_type
          return :pipfile if pipfile && pipfile_lock
          return :poetry if pyproject && pyproject_lock
          return :poetry if pyproject && requirement_files.none?

          :requirements_and_pip_compile
        end

        def requirement_files
          dependency_files.select { |f| f.name.end_with?(".txt", ".in") }
        end

        def pipfile_files_parser
          PipfileFilesParser.new(dependency_files: dependency_files)
        end

        def poetry_files_parser
          PoetryFilesParser.new(dependency_files: dependency_files)
        end

        def requirement_dependencies
          dependencies = DependencySet.new
          parsed_requirement_files.each do |dep|
            requirements =
              if lockfile_for_pip_compile_file?(dep["file"])
                []
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

        def setup_file_dependencies
          dependencies = DependencySet.new
          return dependencies unless setup_file

          parsed_setup_file.each do |dep|
            dependencies <<
              Dependency.new(
                name: normalised_name(dep["name"]),
                version: dep["version"]&.include?("*") ? nil : dep["version"],
                requirements: [{
                  requirement: dep["requirement"],
                  file: Pathname.new(dep["file"]).cleanpath.to_path,
                  source: nil,
                  groups: []
                }],
                package_manager: "pip"
              )
          end
          dependencies
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
              command: "pyenv exec python #{python_helper_path}",
              function: "parse_requirements",
              args: [Dir.pwd]
            )

            check_requirements(requirements)
            requirements
          end
        rescue SharedHelpers::HelperSubprocessFailed => error
          evaluation_errors =
            %w(InstallationError RequirementsFileParseError InvalidMarker)
          raise unless error.message.start_with?(*evaluation_errors)

          raise Dependabot::DependencyFileNotEvaluatable, error.message
        end

        def parsed_setup_file
          SharedHelpers.in_a_temporary_directory do
            write_temporary_dependency_files

            requirements = SharedHelpers.run_helper_subprocess(
              command: "pyenv exec python #{python_helper_path}",
              function: "parse_setup",
              args: [Dir.pwd]
            )

            check_requirements(requirements)
            requirements
          end
        rescue SharedHelpers::HelperSubprocessFailed => error
          raise unless error.message.start_with?("InstallationError")
          raise Dependabot::DependencyFileNotEvaluatable, error.message
        end

        def check_requirements(requirements)
          requirements.each do |dep|
            next unless dep["requirement"]
            Utils::Python::Requirement.new(dep["requirement"].split(","))
          rescue Gem::Requirement::BadRequirementError => error
            raise Dependabot::DependencyFileNotEvaluatable, error.message
          end
        end

        def write_temporary_dependency_files
          dependency_files.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, file.content)
          end
        end

        def python_helper_path
          project_root = File.join(File.dirname(__FILE__), "../../../..")
          File.join(project_root, "helpers/python/run.py")
        end

        # See https://www.python.org/dev/peps/pep-0503/#normalized-names
        def normalised_name(name)
          name.downcase.tr("_", "-").tr(".", "-")
        end

        def check_required_files
          filenames = dependency_files.map(&:name)
          return if filenames.any? { |name| name.end_with?(".txt") }
          return if filenames.any? { |name| name.end_with?(".in") }
          return if (%w(Pipfile Pipfile.lock) - filenames).empty?
          return if get_original_file("pyproject.toml")
          return if get_original_file("setup.py")
          raise "No requirements.txt or setup.py!"
        end

        def pipfile
          @pipfile ||= get_original_file("Pipfile")
        end

        def pipfile_lock
          @pipfile_lock ||= get_original_file("Pipfile.lock")
        end

        def pyproject
          @pyproject ||= get_original_file("pyproject.toml")
        end

        def pyproject_lock
          @pyproject_lock ||= get_original_file("pyproject.lock")
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
end
