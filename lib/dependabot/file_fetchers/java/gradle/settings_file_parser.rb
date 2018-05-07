# frozen_string_literal: true

require "dependabot/file_fetchers/java/gradle"
require "dependabot/shared_helpers"

module Dependabot
  module FileFetchers
    module Java
      class Gradle
        class SettingsFileParser
          def initialize(settings_file:)
            @settings_file = settings_file
          end

          def subproject_paths
            parsed_settings_file.
              fetch("subproject_paths").
              uniq
          end

          private

          attr_reader :settings_file

          def parsed_settings_file
            @parsed_settings_file ||=
              SharedHelpers.in_a_temporary_directory do
                write_temporary_files

                command = "java -jar #{gradle_settings_parser_path} #{Dir.pwd}"
                raw_response = nil
                IO.popen(command) { |process| raw_response = process.read }

                unless $CHILD_STATUS.success?
                  raise SharedHelpers::HelperSubprocessFailed.new(
                    raw_response,
                    command
                  )
                end

                result = File.read("result.json")
                JSON.parse(result)
              end
          end

          def write_temporary_files
            File.write(
              "settings.gradle",
              prepared_settings_file_content(settings_file.content)
            )
          end

          def gradle_settings_parser_path
            "#{gradle_helper_path}/settings_file_parser.jar"
          end

          def gradle_helper_path
            File.join(project_root, "helpers/gradle/")
          end

          def project_root
            File.join(File.dirname(__FILE__), "../../../../..")
          end

          def prepared_settings_file_content(settings_file_content)
            settings_file_content.gsub(/^\s*import\s.*$/, "")
          end
        end
      end
    end
  end
end
