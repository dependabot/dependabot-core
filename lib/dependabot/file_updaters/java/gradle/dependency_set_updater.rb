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
            regex = FileParsers::Java::Gradle::DEPENDENCY_SET_DECLARATION_REGEX
            original_declaration_string =
              buildfile.content.scan(regex) do
                mtch = Regexp.last_match
                next unless mtch.to_s.include?(dependency_set[:group])
                next unless mtch.to_s.include?(dependency_set[:version])

                break mtch.to_s
              end

            updated_content = buildfile.content.sub(
              original_declaration_string,
              original_declaration_string.sub(
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
