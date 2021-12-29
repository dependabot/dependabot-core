# frozen_string_literal: true

require "nokogiri"
require "dependabot/nuget/file_updater"

module Dependabot
  module Nuget
    class FileUpdater
      class ProjectFileDeclarationFinder
        DECLARATION_REGEX =
          %r{
            <PackageReference [^>]*?/>|
            <PackageReference [^>]*?[^/]>.*?</PackageReference>|
            <GlobalPackageReference [^>]*?/>|
            <GlobalPackageReference [^>]*?[^/]>.*?</GlobalPackageReference>|
            <PackageVersion [^>]*?/>|
            <PackageVersion [^>]*?[^/]>.*?</PackageVersion>|
            <Dependency [^>]*?/>|
            <Dependency [^>]*?[^/]>.*?</Dependency>|
            <DevelopmentDependency [^>]*?/>|
            <DevelopmentDependency [^>]*?[^/]>.*?</DevelopmentDependency>
          }mx.freeze
        SDK_IMPORT_REGEX =
          / <Import [^>]*?Sdk="[^"]*?"[^>]*?Version="[^"]*?"[^>]*?>
          | <Import [^>]*?Version="[^"]*?"[^>]*?Sdk="[^"]*?"[^>]*?>
          /mx.freeze
        SDK_PROJECT_REGEX =
          / <Project [^>]*?Sdk="[^"]*?"[^>]*?>
          /mx.freeze
        SDK_SDK_REGEX =
          / <Sdk [^>]*?Name="[^"]*?"[^>]*?Version="[^"]*?"[^>]*?>
          | <Sdk [^>]*?Version="[^"]*?"[^>]*?Name="[^"]*?"[^>]*?>
          /mx.freeze

        attr_reader :dependency_name, :declaring_requirement,
                    :dependency_files

        def initialize(dependency_name:, dependency_files:,
                       declaring_requirement:)
          @dependency_name       = dependency_name
          @dependency_files      = dependency_files
          @declaring_requirement = declaring_requirement
        end

        def declaration_strings
          @declaration_strings ||= fetch_declaration_strings
          @declaration_strings += fetch_sdk_strings
        end

        def declaration_nodes
          declaration_strings.map do |declaration_string|
            Nokogiri::XML(declaration_string)
          end
        end

        private

        def get_element_from_node(node)
          node.at_xpath("/PackageReference") ||
            node.at_xpath("/GlobalPackageReference") ||
            node.at_xpath("/PackageVersion") ||
            node.at_xpath("/Dependency") ||
            node.at_xpath("/DevelopmentDependency")
        end

        # rubocop:disable Metrics/CyclomaticComplexity
        # rubocop:disable Metrics/PerceivedComplexity
        def fetch_declaration_strings
          deep_find_declarations(declaring_file.content).select do |nd|
            node = Nokogiri::XML(nd)
            node.remove_namespaces!
            node = get_element_from_node(node)

            node_name = node.attribute("Include")&.value&.strip ||
                        node.at_xpath("./Include")&.content&.strip ||
                        node.attribute("Update")&.value&.strip ||
                        node.at_xpath("./Update")&.content&.strip
            next false unless node_name&.downcase == dependency_name&.downcase

            node_requirement = get_node_version_value(node)
            node_requirement == declaring_requirement.fetch(:requirement)
          end
        end
        # rubocop:enable Metrics/PerceivedComplexity
        # rubocop:enable Metrics/CyclomaticComplexity

        def fetch_sdk_strings
          sdk_project_strings + sdk_sdk_strings + sdk_import_strings
        end

        # rubocop:disable Metrics/PerceivedComplexity
        def get_node_version_value(node)
          attribute = "Version"
          node.attribute(attribute)&.value&.strip ||
            node.at_xpath("./#{attribute}")&.content&.strip ||
            node.attribute(attribute.downcase)&.value&.strip ||
            node.at_xpath("./#{attribute.downcase}")&.content&.strip
        end
        # rubocop:enable Metrics/PerceivedComplexity

        def deep_find_declarations(string)
          string.scan(DECLARATION_REGEX).flat_map do |matching_node|
            [matching_node, *deep_find_declarations(matching_node[0..-2])]
          end
        end

        def declaring_file
          filename = declaring_requirement.fetch(:file)
          declaring_file = dependency_files.find { |f| f.name == filename }
          return declaring_file if declaring_file

          raise "No file found with name #{filename}!"
        end

        def sdk_import_strings
          sdk_strings(SDK_IMPORT_REGEX, "Import", "Sdk", "Version")
        end

        def parse_element(string, name)
          xml = string
          xml += "</#{name}>" unless string.end_with?("/>")
          node = Nokogiri::XML(xml)
          node.remove_namespaces!
          node.at_xpath("/#{name}")
        end

        def get_attribute_value_nocase(element, name)
          value = element.attribute(name)&.value ||
                  element.attribute(name.downcase)&.value ||
                  element.attribute(name.upcase)&.value
          value&.strip
        end

        def desired_sdk_reference?(sdk_reference, dep_name, dep_version)
          parts = sdk_reference.split("/")
          parts.length == 2 && parts[0]&.downcase == dep_name && parts[1] == dep_version
        end

        def sdk_project_strings
          dep_name = dependency_name&.downcase
          dep_version = declaring_requirement.fetch(:requirement)
          strings = []
          declaring_file.content.scan(SDK_PROJECT_REGEX).each do |string|
            element = parse_element(string, "Project")
            next unless element

            sdk_references = get_attribute_value_nocase(element, "Sdk")
            next unless sdk_references&.include?("/")

            sdk_references.split(";").each do |sdk_reference|
              strings << sdk_reference if desired_sdk_reference?(sdk_reference, dep_name, dep_version)
            end
          end
          strings.uniq
        end

        def sdk_sdk_strings
          sdk_strings(SDK_SDK_REGEX, "Sdk", "Name", "Version")
        end

        def sdk_strings(regex, element_name, name_attribute, version_attribute)
          dep_name = dependency_name&.downcase
          dep_version = declaring_requirement.fetch(:requirement)
          strings = []
          declaring_file.content.scan(regex).each do |string|
            element = parse_element(string, element_name)
            next unless element

            node_name = get_attribute_value_nocase(element, name_attribute)&.downcase
            next unless node_name == dep_name

            node_version = get_attribute_value_nocase(element, version_attribute)
            next unless node_version == dep_version

            strings << string
          end
          strings
        end
      end
    end
  end
end
