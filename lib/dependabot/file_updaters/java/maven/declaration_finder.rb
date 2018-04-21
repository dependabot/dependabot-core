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
            Nokogiri::XML(declaration_string)
          end

          def version_comes_from_property?
            return false unless declaration_node.at_css("version")

            declaration_node.at_css("version").content.strip.
              match?(FileParsers::Java::Maven::PROPERTY_REGEX)
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
            deep_find_declarations(declaring_pom.content).find do |node|
              node = Nokogiri::XML(node)
              node_name = [
                node.at_css("groupId")&.content&.strip,
                node.at_css("artifactId")&.content&.strip
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
            version = dependency_node.at_css("version").content.strip

            unless version.match?(FileParsers::Java::Maven::PROPERTY_REGEX)
              return version
            end

            property_name =
              version.match(FileParsers::Java::Maven::PROPERTY_REGEX).
              named_captures.fetch("property")

            prop_value =
              FileParsers::Java::Maven::PropertyValueFinder.
              new(dependency_files: dependency_files).
              property_details(
                property_name: property_name,
                callsite_pom: declaring_pom
              ).fetch(:value)

            version.gsub(FileParsers::Java::Maven::PROPERTY_REGEX, prop_value)
          end
        end
      end
    end
  end
end
