# frozen_string_literal: true

require "toml-rb"
require "open3"
require "dependabot/errors"
require "dependabot/shared_helpers"
require "dependabot/python/file_parser"
require "dependabot/python/requirement"

module Dependabot
  module Python
    class FileParser
      class PythonRequirementParser
        attr_reader :dependency_files

        def initialize(dependency_files:)
          @dependency_files = dependency_files
        end

        def user_specified_requirements
          [
            pipfile_python_requirement,
            pyproject_python_requirement,
            python_version_file_version,
            runtime_file_python_version,
            setup_file_requirement
          ].compact
        end

        # TODO: Add better Python version detection using dependency versions
        # (e.g., Django 2.x implies Python 3)
        def imputed_requirements
          requirement_files.flat_map do |file|
            file.content.lines.
              select { |l| l.include?(";") && l.include?("python") }.
              filter_map { |l| l.match(/python_version(?<req>.*?["'].*?['"])/) }.
              map { |re| re.named_captures.fetch("req").gsub(/['"]/, "") }.
              select { |r| valid_requirement?(r) }
          end
        end

        private

        def pipfile_python_requirement
          return unless pipfile

          parsed_pipfile = TomlRB.parse(pipfile.content)
          requirement =
            parsed_pipfile.dig("requires", "python_full_version") ||
            parsed_pipfile.dig("requires", "python_version")
          return unless requirement&.match?(/^\d/)

          requirement
        end

        def pyproject_python_requirement
          return unless pyproject

          pyproject_object = TomlRB.parse(pyproject.content)
          poetry_object = pyproject_object.dig("tool", "poetry")

          poetry_object&.dig("dependencies", "python") ||
            poetry_object&.dig("dev-dependencies", "python")
        end

        def python_version_file_version
          return unless python_version_file

          file_version = python_version_file.content.strip
          return if file_version&.empty?
          return unless pyenv_versions.include?("#{file_version}\n")

          file_version
        end

        def runtime_file_python_version
          return unless runtime_file

          file_version = runtime_file.content.
                         match(/(?<=python-).*/)&.to_s&.strip
          return if file_version&.empty?
          return unless pyenv_versions.include?("#{file_version}\n")

          file_version
        end

        def setup_file_requirement
          return unless setup_file

          req = setup_file.content.
                match(/python_requires\s*=\s*['"](?<req>[^'"]+)['"]/)&.
                named_captures&.fetch("req")&.strip

          requirement_class.new(req)
          req
        rescue Gem::Requirement::BadRequirementError
          nil
        end

        def pyenv_versions
          @pyenv_versions ||= run_command("pyenv install --list")
        end

        def run_command(command, env: {})
          start = Time.now
          command = SharedHelpers.escape_command(command)
          stdout, process = Open3.capture2e(env, command)
          time_taken = Time.now - start

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

        def requirement_class
          Dependabot::Python::Requirement
        end

        def valid_requirement?(req_string)
          requirement_class.new(req_string)
          true
        rescue Gem::Requirement::BadRequirementError
          false
        end

        def pipfile
          dependency_files.find { |f| f.name == "Pipfile" }
        end

        def pipfile_lock
          dependency_files.find { |f| f.name == "Pipfile.lock" }
        end

        def pyproject
          dependency_files.find { |f| f.name == "pyproject.toml" }
        end

        def setup_file
          dependency_files.find { |f| f.name == "setup.py" }
        end

        def python_version_file
          dependency_files.find { |f| f.name == ".python-version" }
        end

        def runtime_file
          dependency_files.find { |f| f.name.end_with?("runtime.txt") }
        end

        def requirement_files
          dependency_files.select { |f| f.name.end_with?(".txt") }
        end
      end
    end
  end
end
