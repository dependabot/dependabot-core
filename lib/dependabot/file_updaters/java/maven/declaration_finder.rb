# frozen_string_literal: true

require "dependabot/file_updaters/java/maven"

module Dependabot
  module FileUpdaters
    module Java
      class Maven
        class DeclarationFinder
          DECLARATION_REGEX =
            %r{<parent>.*?</parent>|<dependency>.*?</dependency>|
               <plugin>.*?</plugin>}mx

          attr_reader :dependency_name, :pom_content

          def initialize(dependency_name:, pom_content:)
            @dependency_name = dependency_name
            @pom_content = pom_content
          end

          def declaration_string
            original_pom_declaration
          end

          def declaration_node
            Nokogiri::XML(declaration_string)
          end

          private

          def original_pom_declaration
            deep_find_declarations(pom_content).find do |node|
              node = Nokogiri::XML(node)
              node_name = [
                node.at_css("groupId")&.content,
                node.at_css("artifactId")&.content
              ].compact.join(":")
              node_name == dependency_name
            end
          end

          def deep_find_declarations(string)
            string.scan(DECLARATION_REGEX).flat_map do |matching_node|
              [matching_node, *deep_find_declarations(matching_node[0..-2])]
            end
          end
        end
      end
    end
  end
end
