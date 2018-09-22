# frozen_string_literal: true

require "nokogiri"

require "dependabot/dependency_file"
require "dependabot/file_updaters/dotnet/nuget"
require "dependabot/file_parsers/dotnet/nuget/property_value_finder"

module Dependabot
  module FileUpdaters
    module Dotnet
      class Nuget
        class PropertyValueUpdater
          def initialize(dependency_files:)
            @dependency_files = dependency_files
          end

          def update_file_for_property_change(property_name:, updated_value:,
                                              callsite_file:)
            declaration_details =
              property_value_finder.
              property_details(
                property_name: property_name,
                callsite_file: callsite_file
              )

            node = declaration_details.fetch(:node)

            updated_content = callsite_file.content.sub(
              %r{<#{Regexp.quote(node.name)}>
                 \s*#{Regexp.quote(node.content)}\s*
                 </#{Regexp.quote(node.name)}>}xm,
              "<#{node.name}>#{updated_value}</#{node.name}>"
            )

            update_file(file: callsite_file, content: updated_content)
          end

          private

          attr_reader :dependency_files

          def property_value_finder
            @property_value_finder ||=
              FileParsers::Dotnet::Nuget::PropertyValueFinder.
              new(dependency_files: dependency_files)
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
