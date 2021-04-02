# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/errors"
require "dependabot/file_parsers/base/dependency_set"
require "dependabot/shared_helpers"
require "dependabot/python/requirement"
require "dependabot/python/native_helpers"
require "dependabot/python/name_normaliser"

module Dependabot
  module Python
    class FileParser
      class SetupFileParserBase
        def initialize(dependency_files:)
          @dependency_files = dependency_files
        end

        def dependency_set
          dependencies = Dependabot::FileParsers::Base::DependencySet.new

          parsed_setup_file.each do |dep|
            # If a requirement has a `<` or `<=` marker then updating it is
            # probably blocked. Ignore it.
            next if dep["markers"].include?("<")

            # If the requirement is our inserted version, ignore it
            # (we wouldn't be able to update it)
            next if dep["version"] == "0.0.1+dependabot"

            dependencies <<
              Dependency.new(
                name: normalised_name(dep["name"], dep["extras"]),
                version: dep["version"]&.include?("*") ? nil : dep["version"],
                requirements: [{
                  requirement: dep["requirement"],
                  file: Pathname.new(dep["file"]).cleanpath.to_path,
                  source: nil,
                  groups: [dep["requirement_type"]]
                }],
                package_manager: "pip"
              )
          end
          dependencies
        end

        private

        attr_reader :dependency_files

        def function
          "parse_setup"
        end

        def parsed_setup_file
          SharedHelpers.in_a_temporary_directory do
            write_temporary_dependency_files

            requirements = SharedHelpers.run_helper_subprocess(
              command: "python #{NativeHelpers.python_helper_path}",
              function: function,
              args: [Dir.pwd]
            )

            check_requirements(requirements)
            requirements
          end
        rescue SharedHelpers::HelperSubprocessFailed => e
          raise Dependabot::DependencyFileNotEvaluatable, e.message if e.message.start_with?("InstallationError")

          parsed_sanitized_setup_file
        end

        def parsed_sanitized_setup_file
          []
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
              File.write(path, file.content)
            end
        end

        def normalised_name(name, extras)
          NameNormaliser.normalise_including_extras(name, extras)
        end
      end
    end
  end
end
