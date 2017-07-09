# frozen_string_literal: true
require "dependabot/dependency"
require "dependabot/file_parsers/base"
require "dependabot/file_fetchers/python/pip"
require "dependabot/shared_helpers"

module Dependabot
  module FileParsers
    module Python
      class Pip < Dependabot::FileParsers::Base
        def parse
          dependency_versions.map do |dep|
            Dependency.new(
              name: dep["name"],
              version: dep["version"],
              package_manager: "pip"
            )
          end
        end

        private

        def dependency_versions
          SharedHelpers.in_a_temporary_directory do |dir|
            File.write(File.join(dir, "requirements.txt"), requirements.content)

            SharedHelpers.run_helper_subprocess(
              command: "python #{python_helper_path}",
              function: "parse",
              args: [dir]
            )
          end
        rescue SharedHelpers::HelperSubprocessFailed => error
          raise unless error.message.start_with?("InstallationError")
          raise Dependabot::DependencyFileNotEvaluatable, error.message
        end

        def python_helper_path
          project_root = File.join(File.dirname(__FILE__), "../../../..")
          File.join(project_root, "helpers/python/run.py")
        end

        def required_files
          Dependabot::FileFetchers::Python::Pip.required_files
        end

        def requirements
          @requirements ||= get_original_file("requirements.txt")
        end
      end
    end
  end
end
