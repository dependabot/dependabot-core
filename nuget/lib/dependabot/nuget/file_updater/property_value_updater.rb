# typed: strict
# frozen_string_literal: true

require "nokogiri"

require "dependabot/dependency_file"
require "dependabot/nuget/file_updater"
require "dependabot/nuget/file_parser/property_value_finder"

module Dependabot
  module Nuget
    class FileUpdater
      class PropertyValueUpdater
        extend T::Sig

        sig { params(dependency_files: T::Array[Dependabot::DependencyFile]).void }
        def initialize(dependency_files:)
          @dependency_files = dependency_files
        end

        sig do
          params(property_name: String,
                 updated_value: String,
                 callsite_file: Dependabot::DependencyFile)
            .returns(T::Array[Dependabot::DependencyFile])
        end
        def update_files_for_property_change(property_name:, updated_value:,
                                             callsite_file:)
          declaration_details =
            property_value_finder.property_details(
              property_name: property_name,
              callsite_file: callsite_file
            )
          throw "Unable to locate property details" unless declaration_details

          declaration_filename = declaration_details.fetch(:file)
          declaration_file = dependency_files.find do |f|
            declaration_filename == f.name
          end
          throw "Unable to locate declaration file" unless declaration_file

          content = T.must(declaration_file.content)
          node = declaration_details.fetch(:node)

          updated_content = content.sub(
            %r{(<#{Regexp.quote(node.name)}(?:\s[^>]*)?>)
               \s*#{Regexp.quote(node.content)}\s*
               </#{Regexp.quote(node.name)}>}xm,
            '\1' + "#{updated_value}</#{node.name}>"
          )

          files = dependency_files.dup
          file_index = T.must(files.index(declaration_file))
          files[file_index] =
            update_file(file: declaration_file, content: updated_content)
          files
        end

        private

        sig { returns(T::Array[DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(FileParser::PropertyValueFinder) }
        def property_value_finder
          @property_value_finder ||=
            T.let(FileParser::PropertyValueFinder
            .new(dependency_files: dependency_files), T.nilable(FileParser::PropertyValueFinder))
        end

        sig { params(file: DependencyFile, content: String).returns(DependencyFile) }
        def update_file(file:, content:)
          updated_file = file.dup
          updated_file.content = content
          updated_file
        end
      end
    end
  end
end
