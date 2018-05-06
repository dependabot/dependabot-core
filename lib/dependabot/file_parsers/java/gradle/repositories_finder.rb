# frozen_string_literal: true

require "dependabot/file_parsers/java/gradle"
require "dependabot/shared_helpers"

module Dependabot
  module FileParsers
    module Java
      class Gradle
        class RepositoriesFinder
          # The Central Repo doesn't have special status for Gradle, but until
          # we're confident we're selecting repos correctly it's wise to include
          # it as a default.
          CENTRAL_REPO_URL = "https://repo.maven.apache.org/maven2"

          def initialize(dependency_files:)
            @dependency_files = dependency_files
          end

          def repository_urls
            repository_urls =
              parsed_buildfile.
              fetch("repositories").
              map { |details| details.fetch("url") }.
              map { |url| url.strip.gsub(%r{/$}, "") }.
              uniq

            return repository_urls unless repository_urls.empty?

            [CENTRAL_REPO_URL]
          end

          private

          attr_reader :dependency_files

          def parsed_buildfile
            @parsed_buildfile ||=
              SharedHelpers.in_a_temporary_directory do
                write_temporary_files

                command = "java -jar #{gradle_parser_path} #{Dir.pwd}"
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
              "build.gradle",
              prepared_buildfile_content(buildfile.content)
            )
          end

          def gradle_parser_path
            "#{gradle_helper_path}/buildfile_parser.jar"
          end

          def gradle_helper_path
            File.join(project_root, "helpers/gradle/")
          end

          def project_root
            File.join(File.dirname(__FILE__), "../../../../..")
          end

          def prepared_buildfile_content(buildfile_content)
            buildfile_content.gsub(/^\s*import\s.*$/, "")
          end

          def buildfile
            @buildfile ||=
              dependency_files.find { |f| f.name == "build.gradle" }
          end
        end
      end
    end
  end
end
