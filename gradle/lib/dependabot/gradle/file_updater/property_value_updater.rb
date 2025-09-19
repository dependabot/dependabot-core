# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/gradle/file_updater"
require "dependabot/gradle/file_parser/property_value_finder"

module Dependabot
  module Gradle
    class FileUpdater
      class PropertyValueUpdater
        extend T::Sig

        sig { params(dependency_files: T::Array[DependencyFile]).void }
        def initialize(dependency_files:)
          @dependency_files = dependency_files
          @property_value_finder = T.let(nil, T.nilable(Gradle::FileParser::PropertyValueFinder))
        end

        sig do
          params(
            property_name: String,
            callsite_buildfile: DependencyFile,
            previous_value: String,
            updated_value: String
          )
            .returns(T::Array[DependencyFile])
        end
        def update_files_for_property_change(property_name:,
                                             callsite_buildfile:,
                                             previous_value:,
                                             updated_value:)
          declaration_details = T.must(
            property_value_finder.property_details(
              property_name: property_name,
              callsite_buildfile: callsite_buildfile
            )
          )
          declaration_string = declaration_details.fetch(:declaration_string)
          filename = declaration_details.fetch(:file)

          file_to_update = T.must(dependency_files.find { |f| f.name == filename })
          updated_content = T.must(file_to_update.content).sub(
            declaration_string,
            declaration_string.sub(
              previous_value_regex(previous_value),
              updated_value
            )
          )

          updated_files = dependency_files.dup
          updated_files[T.must(updated_files.index(file_to_update))] =
            update_file(file: file_to_update, content: updated_content)

          updated_files
        end

        private

        sig { returns(T::Array[DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(Gradle::FileParser::PropertyValueFinder) }
        def property_value_finder
          @property_value_finder ||=
            Gradle::FileParser::PropertyValueFinder
            .new(dependency_files: dependency_files)
        end

        sig { params(file: DependencyFile, content: String).returns(DependencyFile) }
        def update_file(file:, content:)
          updated_file = file.dup
          updated_file.content = content
          updated_file
        end

        sig { params(previous_value: String).returns(Regexp) }
        def previous_value_regex(previous_value)
          /(?<=['"])#{Regexp.quote(previous_value)}(?=['"])/
        end
      end
    end
  end
end
