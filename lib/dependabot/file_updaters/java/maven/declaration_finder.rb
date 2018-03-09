# frozen_string_literal: true

require "nokogiri"
require "dependabot/file_updaters/java/maven"

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
            declaration_node.at_css("version").content.start_with?("${")
          end

          private

          def find_pom_declaration_string
            deep_find_declarations(pom_content).find do |node|
              node = Nokogiri::XML(node)
              node_name = [
                node.at_css("groupId")&.content,
                node.at_css("artifactId")&.content
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
            version_content = dependency_node.at_css("version").content

            return version_content unless version_content.start_with?("${")

            property_name = version_content.strip[2..-2]
            doc = Nokogiri::XML(pom_content)
            doc.remove_namespaces!
            if property_name.start_with?("project.")
              path = "//project/#{property_name.gsub(/^project\./, '')}"
              doc.at_xpath(path)&.content ||
                doc.at_xpath("//properties/#{property_name}").content
            else
              doc.at_xpath("//properties/#{property_name}").content
            end
          end
        end
      end
    end
  end
end
