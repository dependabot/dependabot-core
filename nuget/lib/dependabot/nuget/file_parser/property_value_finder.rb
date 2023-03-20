# frozen_string_literal: true

require "dependabot/nuget/file_fetcher/import_paths_finder"
require "dependabot/nuget/file_parser"

# For docs, see:
# - https://docs.microsoft.com/en-us/visualstudio/msbuild/msbuild-properties
# - https://docs.microsoft.com/en-us/visualstudio/msbuild/customize-your-build
module Dependabot
  module Nuget
    class FileParser
      class PropertyValueFinder
        PROPERTY_REGEX = /\$\((?<property>.*?)\)/

        def initialize(dependency_files:)
          @dependency_files = dependency_files
        end

        def property_details(property_name:, callsite_file:, stack: [])
          stack += [[property_name, callsite_file.name]]
          return if property_name.include?("(")

          node_details = deep_find_prop_node(
            property: property_name,
            file: callsite_file
          )

          node_details ||=
            find_property_in_directory_build_targets(
              property: property_name,
              callsite_file: callsite_file
            )

          node_details ||=
            find_property_in_directory_build_props(
              property: property_name,
              callsite_file: callsite_file
            )

          node_details ||=
            find_property_in_directory_build_packages(
              property: property_name,
              callsite_file: callsite_file
            )

          node_details ||=
            find_property_in_packages_props(property: property_name)

          return unless node_details
          return node_details unless PROPERTY_REGEX.match?(node_details[:value])

          check_next_level_of_stack(node_details, stack)
        end

        def check_next_level_of_stack(node_details, stack)
          property_name = node_details.fetch(:value).
                          match(PROPERTY_REGEX).
                          named_captures.fetch("property")
          callsite_file = dependency_files.
                          find { |f| f.name == node_details.fetch(:file) }

          raise "Circular reference!" if stack.include?([property_name, callsite_file.name])

          property_details(
            property_name: property_name,
            callsite_file: callsite_file,
            stack: stack
          )
        end

        private

        attr_reader :dependency_files

        def deep_find_prop_node(property:, file:)
          doc = Nokogiri::XML(file.content)
          doc.remove_namespaces!
          node = doc.at_xpath(property_xpath(property))

          # If we found a value for the property, return it
          return node_details(file: file, node: node, property: property) if node

          # Otherwise, we need to look in an imported file
          import_path_finder =
            Nuget::FileFetcher::ImportPathsFinder.
            new(project_file: file)

          import_paths = [
            *import_path_finder.import_paths,
            *import_path_finder.project_reference_paths
          ]

          file = import_paths.
                 filter_map { |p| dependency_files.find { |f| f.name == p } }.
                 find { |f| deep_find_prop_node(property: property, file: f) }

          return unless file

          deep_find_prop_node(property: property, file: file)
        end

        def find_property_in_directory_build_targets(property:, callsite_file:)
          file = build_targets_file_for_project(callsite_file)
          return unless file

          deep_find_prop_node(property: property, file: file)
        end

        def find_property_in_directory_build_props(property:, callsite_file:)
          file = build_props_file_for_project(callsite_file)
          return unless file

          deep_find_prop_node(property: property, file: file)
        end

        def find_property_in_directory_build_packages(property:, callsite_file:)
          file = build_packages_file_for_project(callsite_file)
          return unless file

          deep_find_prop_node(property: property, file: file)
        end

        def find_property_in_packages_props(property:)
          file = packages_props_file
          return unless file

          deep_find_prop_node(property: property, file: file)
        end

        def build_targets_file_for_project(project_file)
          dir = File.dirname(project_file.name)

          # Nuget walks up the directory structure looking for a
          # Directory.Build.targets file
          possible_paths = dir.split("/").map.with_index do |_, i|
            base = dir.split("/").first(i + 1).join("/")
            Pathname.new(base + "/Directory.Build.targets").cleanpath.to_path
          end.reverse + ["Directory.Build.targets"]

          path = possible_paths.uniq.
                 find { |p| dependency_files.find { |f| f.name == p } }

          dependency_files.find { |f| f.name == path }
        end

        def build_props_file_for_project(project_file)
          dir = File.dirname(project_file.name)

          # Nuget walks up the directory structure looking for a
          # Directory.Build.props file
          possible_paths = dir.split("/").map.with_index do |_, i|
            base = dir.split("/").first(i + 1).join("/")
            Pathname.new(base + "/Directory.Build.props").cleanpath.to_path
          end.reverse + ["Directory.Build.props"]

          path =
            possible_paths.uniq.
            find { |p| dependency_files.find { |f| f.name.casecmp(p).zero? } }

          dependency_files.find { |f| f.name == path }
        end

        def build_packages_file_for_project(project_file)
          dir = File.dirname(project_file.name)

          # Nuget walks up the directory structure looking for a
          # Directory.Packages.props file
          possible_paths = dir.split("/").map.with_index do |_, i|
            base = dir.split("/").first(i + 1).join("/")
            Pathname.new(base + "/Directory.Packages.props").cleanpath.to_path
          end.reverse + ["Directory.Packages.props"]

          path = possible_paths.uniq.
                 find { |p| dependency_files.find { |f| f.name == p } }

          dependency_files.find { |f| f.name == path }
        end

        def packages_props_file
          dependency_files.find { |f| f.name.casecmp("Packages.props").zero? }
        end

        def property_xpath(property_name)
          "/Project/PropertyGroup/#{property_name}"
        end

        def node_details(file:, node:, property:)
          {
            file: file.name,
            node: node,
            value: node.content.strip,
            root_property_name: property
          }
        end
      end
    end
  end
end
