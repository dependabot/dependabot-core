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
            node_details = deep_find_prop_node(
              property: property_name,
              file: callsite_file
            )

            node_details ||=
              find_property_in_directory_build_props(
                property: property_name,
                callsite_file: callsite_file
              )

            node_details
          end

          private

          attr_reader :dependency_files

          def deep_find_prop_node(property:, file:)
            doc = Nokogiri::XML(file.content)
            doc.remove_namespaces!
            node = doc.at_xpath(property_xpath(property))

            # If we found a value for the property, return it
            return node_details(file: file, node: node) if node

            # Otherwise, we need to look in an imported file
            import_path_finder =
              FileFetchers::Dotnet::Nuget::ImportPathsFinder.
              new(project_file: file)

            import_paths = [
              *import_path_finder.import_paths,
              *import_path_finder.project_reference_paths
            ]

            file = import_paths.
                   map { |p| dependency_files.find { |f| f.name == p } }.
                   compact.
                   find { |f| deep_find_prop_node(property: property, file: f) }

            return unless file

            deep_find_prop_node(property: property, file: file)
          end

          def find_property_in_directory_build_props(property:, callsite_file:)
            file = buildfile_for_project(callsite_file)
            return unless file

            deep_find_prop_node(property: property, file: file)
          end

          def buildfile_for_project(project_file)
            dir = File.dirname(project_file.name)

            # Nuget walks up the directory structure looking for a
            # Directory.Build.props file
            possible_paths = dir.split("/").map.with_index do |_, i|
              base = dir.split("/").first(i + 1).join("/")
              Pathname.new(base + "/Directory.Build.props").cleanpath.to_path
            end.reverse + ["Directory.Build.props"]

            path = possible_paths.uniq.
                   find { |p| dependency_files.find { |f| f.name == p } }

            dependency_files.find { |f| f.name == path }
          end

          def property_xpath(property_name)
            "/Project/PropertyGroup/#{property_name}"
          end

          def node_details(file:, node:)
            { file: file.name, node: node, value: node.content.strip }
          end
        end
      end
    end
  end
end
