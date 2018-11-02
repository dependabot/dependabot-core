# frozen_string_literal: true

require "dependabot/file_parsers/java/gradle"
require "dependabot/file_updaters/java/gradle"

module Dependabot
  module FileUpdaters
    module Java
      class Gradle
        class DependencySetUpdater
          def initialize(dependency_files:)
            @dependency_files = dependency_files
          end

          def update_files_for_dep_set_change(dependency_set:,
                                              buildfile:,
                                              previous_requirement:,
                                              updated_requirement:)
            declaration_string =
              original_declaration_string(dependency_set, buildfile)

            return dependency_files unless declaration_string

            updated_content = buildfile.content.sub(
              declaration_string,
              declaration_string.sub(
                previous_requirement,
                updated_requirement
              )
            )

            updated_files = dependency_files.dup
            updated_files[updated_files.index(buildfile)] =
              update_file(file: buildfile, content: updated_content)

            updated_files
          end

          private

          attr_reader :dependency_files

          def original_declaration_string(dependency_set, buildfile)
            regex = FileParsers::Java::Gradle::DEPENDENCY_SET_DECLARATION_REGEX
            dependency_sets = []
            buildfile.content.scan(regex) do
              dependency_sets << Regexp.last_match.to_s
            end

            dependency_sets.find do |mtch|
              next unless mtch.include?(dependency_set[:group])

              mtch.include?(dependency_set[:version])
            end
          end

          def update_file(file:, content:)
            updated_file = file.dup
            updated_file.content = content
            updated_file
          end
        end
      end
    end
  end
end
