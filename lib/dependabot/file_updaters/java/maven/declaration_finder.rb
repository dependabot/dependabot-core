# frozen_string_literal: true

require "nokogiri"
require "dependabot/file_updaters/java/maven"
require "dependabot/file_parsers/java/maven"
require "dependabot/file_parsers/java/maven/property_value_finder"

module Dependabot
  module FileUpdaters
    module Java
      class Maven
        class DeclarationFinder
          DECLARATION_REGEX =
            %r{<parent>.*?</parent>|<dependency>.*?</dependency>|
               <plugin>.*?</plugin>}mx

          attr_reader :dependency, :declaring_requirement, :dependency_files

          def initialize(dependency:, dependency_files:, declaring_requirement:)
            @dependency            = dependency
            @dependency_files      = dependency_files
            @declaring_requirement = declaring_requirement
          end

          def declaration_string
            @declaration_string ||= find_pom_declaration_string
          end

          def declaration_node
            return unless declaration_string
            Nokogiri::XML(declaration_string)
          end

          private

          def declaring_pom
            filename = declaring_requirement.fetch(:file)
            declaring_pom = dependency_files.find { |f| f.name == filename }
            return declaring_pom if declaring_pom
            raise "No pom found with name #{filename}!"
          end

          def dependency_name
            dependency.name
          end

          def find_pom_declaration_string
            deep_find_declarations(declaring_pom.content).find do |nd|
              node = Nokogiri::XML(nd)
              node.remove_namespaces!
              next false unless node.at_xpath("./*/groupId")
              next false unless node.at_xpath("./*/artifactId")

              node_name = [
                evaluated_value(node.at_xpath("./*/groupId").content.strip),
                evaluated_value(node.at_xpath("./*/artifactId").content.strip)
              ].compact.join(":")

              next false unless node_name == dependency_name
              next true unless declaring_requirement.fetch(:requirement)
              dependency_requirement_for_node(node) ==
                declaring_requirement.fetch(:requirement)
            end
          end

          def deep_find_declarations(string)
            string.scan(DECLARATION_REGEX).flat_map do |matching_node|
              [matching_node, *deep_find_declarations(matching_node[0..-2])]
            end
          end

          def dependency_requirement_for_node(dependency_node)
            return unless dependency_node.at_css("version")
            evaluated_value(dependency_node.at_css("version").content.strip)
          end

          def evaluated_value(value)
            unless value.match?(FileParsers::Java::Maven::PROPERTY_REGEX)
              return value
            end

            property_name =
              value.match(FileParsers::Java::Maven::PROPERTY_REGEX).
              named_captures.fetch("property")

            property_value =
              property_value_finder.
              property_details(
                property_name: property_name,
                callsite_pom: declaring_pom
              ).fetch(:value)

            value.gsub(FileParsers::Java::Maven::PROPERTY_REGEX, property_value)
          end

          def property_value_finder
            @property_value_finder ||=
              FileParsers::Java::Maven::PropertyValueFinder.
              new(dependency_files: dependency_files)
          end
        end
      end
    end
  end
end
