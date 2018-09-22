# frozen_string_literal: true

require "dependabot/file_fetchers/dotnet/nuget/import_paths_finder"
require "dependabot/file_parsers/dotnet/nuget"

# For docs, see:
# - https://docs.microsoft.com/en-us/visualstudio/msbuild/msbuild-properties
# - https://docs.microsoft.com/en-us/visualstudio/msbuild/customize-your-build
module Dependabot
  module FileParsers
    module Dotnet
      class Nuget
        class PropertyValueFinder
          def initialize(dependency_files:)
            @dependency_files = dependency_files
          end

          def property_details(property_name:, callsite_file:)
            doc = Nokogiri::XML(callsite_file.content)
            doc.remove_namespaces!

            node = doc.at_xpath("/Project/PropertyGroup/#{property_name}")
            return unless node

            { file: callsite_file.name, node: node, value: node.content.strip }
          end

          private

          attr_reader :dependency_files
        end
      end
    end
  end
end
