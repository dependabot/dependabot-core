# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/file_parsers/base"
require "dependabot/shared_helpers"
require "dependabot/errors"

module Dependabot
  module FileParsers
    module Python
      class Pip < Dependabot::FileParsers::Base
        require "dependabot/file_parsers/base/dependency_set"

        def parse
          dependency_set = DependencySet.new

          dependency_versions.each do |dep|
            next if dep["version"]&.include?("*")
            dependency_set <<
              Dependency.new(
                name: dep["name"],
                version: dep["version"],
                requirements: [
                  {
                    requirement: dep["requirement"],
                    file: Pathname.new(dep["file"]).cleanpath.to_path,
                    source: nil,
                    groups: []
                  }
                ],
                package_manager: "pip"
              )
          end

          dependency_set.dependencies
        end

        private

        def dependency_versions
          SharedHelpers.in_a_temporary_directory do
            write_temporary_dependency_files

            SharedHelpers.run_helper_subprocess(
              command: "python3.6 #{python_helper_path}",
              function: "parse",
              args: [Dir.pwd]
            )
          end
        rescue SharedHelpers::HelperSubprocessFailed => error
          raise unless error.message.start_with?("InstallationError")
          raise Dependabot::DependencyFileNotEvaluatable, error.message
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

        def check_required_files
          return if get_original_file("requirements.txt")
          return if get_original_file("setup.py")
          raise "No requirements.txt or setup.py!"
        end
      end
    end
  end
end
