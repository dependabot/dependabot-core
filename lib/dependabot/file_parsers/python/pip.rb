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

        # TODO: Kill this off once it's unused in file_updater
        class LineParser
          NAME = /[a-zA-Z0-9\-_\.]+/
          EXTRA = /[a-zA-Z0-9\-_\.]+/
          COMPARISON = /===|==|>=|<=|<|>|~=|!=/
          VERSION = /[a-zA-Z0-9\-_\.]+/
          REQUIREMENT = /(?<comparison>#{COMPARISON})\s*(?<version>#{VERSION})/

          REQUIREMENT_LINE =
            /^\s*(?<name>#{NAME})
              \s*(\[\s*(?<extras>#{EXTRA}(\s*,\s*#{EXTRA})*)\s*\])?
              \s*(?<requirements>#{REQUIREMENT}(\s*,\s*#{REQUIREMENT})*)?
              \s*#*\s*(?<comment>.+)?$
            /x

          def self.parse(line)
            requirement = line.chomp.match(REQUIREMENT_LINE)
            return if requirement.nil?

            requirements =
              requirement[:requirements].to_s.
              to_enum(:scan, REQUIREMENT).
              map do
                {
                  comparison: Regexp.last_match[:comparison],
                  version: Regexp.last_match[:version]
                }
              end

            {
              name: requirement[:name],
              requirements: requirements
            }
          end
        end
      end
    end
  end
end
