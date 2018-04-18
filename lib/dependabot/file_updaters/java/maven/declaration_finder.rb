# frozen_string_literal: true

require "nokogiri"
require "dependabot/file_updaters/java/maven"
require "dependabot/file_parsers/java/maven"

module Dependabot
  module FileUpdaters
    module Java
      class Maven
        class DeclarationFinder
          DECLARATION_REGEX =
            %r{<parent>.*?</parent>|<dependency>.*?</dependency>|
               <plugin>.*?</plugin>}mx

          attr_reader :dependency_name, :dependency_requirement, :pom_content

          def initialize(dependency_name:, pom_content:,
                         dependency_requirement: nil)
            @dependency_name = dependency_name
            @dependency_requirement = dependency_requirement
            @pom_content = pom_content
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

          def find_pom_declaration_string
            deep_find_declarations(pom_content).find do |node|
              node = Nokogiri::XML(node)
              node_name = [
                node.at_css("groupId")&.content&.strip,
                node.at_css("artifactId")&.content&.strip
              ].compact.join(":")
              next false unless node_name == dependency_name
              next true unless dependency_requirement
              dependency_requirement_for_node(node) == dependency_requirement
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

            doc = Nokogiri::XML(pom_content)
            doc.remove_namespaces!
            prop_value =
              if property_name.start_with?("project.")
                path = "//project/#{property_name.gsub(/^project\./, '')}"
                doc.at_xpath(path)&.content&.strip ||
                  doc.at_xpath("//properties/#{property_name}").content.strip
              else
                doc.at_xpath("//properties/#{property_name}").content.strip
              end
            version.gsub(FileParsers::Java::Maven::PROPERTY_REGEX, prop_value)
          end
        end
      end
    end
  end
end
