# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/errors"
require "dependabot/file_parsers/base/dependency_set"
require "dependabot/file_parsers/python/pip"
require "dependabot/shared_helpers"

module Dependabot
  module FileParsers
    module Python
      class Pip
        class SetupFileParser
          def initialize(dependency_files:)
            @dependency_files = dependency_files
          end

          def dependency_set
            dependencies = Dependabot::FileParsers::Base::DependencySet.new

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

          private

          attr_reader :dependency_files

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
            project_root = File.join(File.dirname(__FILE__), "../../../../..")
            File.join(project_root, "helpers/python/run.py")
          end

          # See https://www.python.org/dev/peps/pep-0503/#normalized-names
          def normalised_name(name)
            name.downcase.tr("_", "-").tr(".", "-")
          end
        end
      end
    end
  end
end
