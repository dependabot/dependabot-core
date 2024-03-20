# typed: strict
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
        extend T::Sig

        PROPERTY_REGEX = /\$\((?<property>.*?)\)/

        sig { params(dependency_files: T::Array[Dependabot::DependencyFile]).void }
        def initialize(dependency_files:)
          @dependency_files = dependency_files
        end

        sig do
          params(property_name: String,
                 callsite_file: Dependabot::DependencyFile,
                 stack: T::Array[[String, String]])
            .returns(T.nilable(T::Hash[T.untyped, T.untyped]))
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
            find_property_in_directory_packages_props(
              property: property_name,
              callsite_file: callsite_file
            )

          node_details ||=
            find_property_in_packages_props(property: property_name)

          return unless node_details
          return node_details unless PROPERTY_REGEX.match?(node_details[:value])

          check_next_level_of_stack(node_details, stack)
        end

        sig do
          params(node_details: T.untyped,
                 stack: T::Array[[String, String]])
            .returns(T.nilable(T::Hash[T.untyped, T.untyped]))
        end
        def check_next_level_of_stack(node_details, stack)
          property_name = node_details.fetch(:value)
                                      .match(PROPERTY_REGEX)
                                      .named_captures.fetch("property")
          callsite_file = dependency_files
                          .find { |f| f.name == node_details.fetch(:file) }
          return unless callsite_file

          raise "Circular reference!" if stack.include?([property_name, callsite_file.name])

          property_details(
            property_name: property_name,
            callsite_file: callsite_file,
            stack: stack
          )
        end

        private

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig do
          params(property: String,
                 file: Dependabot::DependencyFile)
            .returns(T.nilable(T::Hash[Symbol, T.untyped]))
        end
        def deep_find_prop_node(property:, file:)
          doc = Nokogiri::XML(file.content)
          doc.remove_namespaces!
          node = doc.at_xpath(property_xpath(property))

          # If we found a value for the property, return it
          return node_details(file: file, node: node, property: property) if node

          # Otherwise, we need to look in an imported file
          import_path_finder =
            Nuget::FileFetcher::ImportPathsFinder
            .new(project_file: file)

          import_paths = [
            *import_path_finder.import_paths,
            *import_path_finder.project_reference_paths
          ]

          file = import_paths
                 .filter_map { |p| dependency_files.find { |f| f.name == p } }
                 .find { |f| deep_find_prop_node(property: property, file: f) }

          return unless file

          deep_find_prop_node(property: property, file: file)
        end

        sig do
          params(property: String, callsite_file: Dependabot::DependencyFile)
            .returns(T.nilable(T::Hash[Symbol, T.untyped]))
        end
        def find_property_in_directory_build_targets(property:, callsite_file:)
          find_property_in_up_tree_files(property: property, callsite_file: callsite_file,
                                         expected_file_name: "Directory.Build.targets")
        end

        sig do
          params(property: String, callsite_file: Dependabot::DependencyFile)
            .returns(T.nilable(T::Hash[Symbol, T.untyped]))
        end
        def find_property_in_directory_build_props(property:, callsite_file:)
          find_property_in_up_tree_files(property: property, callsite_file: callsite_file,
                                         expected_file_name: "Directory.Build.props")
        end

        sig do
          params(property: String, callsite_file: Dependabot::DependencyFile)
            .returns(T.nilable(T::Hash[Symbol, T.untyped]))
        end
        def find_property_in_directory_packages_props(property:, callsite_file:)
          find_property_in_up_tree_files(property: property, callsite_file: callsite_file,
                                         expected_file_name: "Directory.Packages.props")
        end

        sig { params(property: String).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
        def find_property_in_packages_props(property:)
          file = packages_props_file
          return unless file

          deep_find_prop_node(property: property, file: file)
        end

        sig do
          params(property: String,
                 callsite_file: Dependabot::DependencyFile,
                 expected_file_name: String)
            .returns(T.untyped)
        end
        def find_property_in_up_tree_files(property:, callsite_file:, expected_file_name:)
          files = up_tree_files_for_project(callsite_file, expected_file_name)
          return if files.empty?

          # first file where we were able to find the node
          files.reduce(T.let(nil, T.nilable(String))) do |acc, file|
            acc || deep_find_prop_node(property: property, file: file)
          end
        end

        sig do
          params(project_file: DependencyFile, expected_file_name: String).returns(T::Array[Dependabot::DependencyFile])
        end
        def up_tree_files_for_project(project_file, expected_file_name)
          dir = File.dirname(project_file.name)

          # Simulate MSBuild walking up the directory structure looking for a file
          possible_paths = dir.split("/").map.with_index do |_, i|
            base = dir.split("/").first(i + 1).join("/")
            Pathname.new(base + "/#{expected_file_name}").cleanpath.to_path
          end.reverse + [expected_file_name]

          paths =
            possible_paths.uniq
                          .select { |p| dependency_files.find { |f| f.name.casecmp(p)&.zero? } }

          dependency_files.select { |f| paths.include?(f.name) }
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def packages_props_file
          dependency_files.find { |f| f.name.casecmp("Packages.props")&.zero? }
        end

        sig { params(property_name: String).returns(String) }
        def property_xpath(property_name)
          # only return properties that don't have a `Condition` attribute or the `Condition` attribute is checking for
          # an empty string, e.g., Condition="$(SomeProperty) == ''"
          %{/Project/PropertyGroup/#{property_name}[not(@Condition) or @Condition="$(#{property_name}) == ''"]}
        end

        sig do
          params(file: DependencyFile,
                 node: Nokogiri::XML::Node,
                 property: String)
            .returns(T::Hash[Symbol, T.untyped])
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
