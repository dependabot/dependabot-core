# frozen_string_literal: true

require "nokogiri"
require "dependabot/file_updaters/base"
require "dependabot/file_parsers/java/maven"

module Dependabot
  module FileUpdaters
    module Java
      class Maven < Dependabot::FileUpdaters::Base
        require "dependabot/file_updaters/java/maven/declaration_finder"

        def self.updated_files_regex
          [/^pom\.xml$/]
        end

        def updated_dependency_files
          [updated_file(file: pom, content: updated_pom_content)]
        end

        private

        def check_required_files
          %w(pom.xml).each do |filename|
            raise "No #{filename}!" unless get_original_file(filename)
          end
        end

        def updated_pom_content
          updated_content =
            if updating_a_property?
              update_property_version
            else
              dependencies.reduce(pom.content.dup) do |content, dep|
                content.gsub(
                  original_pom_declaration(dep),
                  updated_pom_declaration(dep)
                )
              end
            end

          raise "Expected content to change!" if updated_content == pom.content
          updated_content
        end

        def update_property_version
          prop_name = DeclarationFinder.new(
            dependency_name: dependencies.first.name,
            pom_content: pom.content
          ).declaration_node.at_css("version").content.strip[2..-2]

          original_requirement = original_pom_requirement(dependencies.first)
          updated_requirement = updated_pom_requirement(dependencies.first)

          pom.content.gsub(
            "<#{prop_name}>#{original_requirement}</#{prop_name}>",
            "<#{prop_name}>#{updated_requirement}</#{prop_name}>"
          )
        end

        def original_pom_version_content
          Nokogiri::XML(original_pom_declaration).at_css("version").content
        end

        def updating_a_property?
          DeclarationFinder.new(
            dependency_name: dependencies.first.name,
            pom_content: pom.content
          ).version_comes_from_property?
        end

        def original_pom_declaration(dependency)
          DeclarationFinder.new(
            dependency_name: dependency.name,
            pom_content: pom.content
          ).declaration_string
        end

        def updated_pom_declaration(dependency)
          original_pom_declaration(dependency).gsub(
            "<version>#{original_pom_requirement(dependency)}</version>",
            "<version>#{updated_pom_requirement(dependency)}</version>"
          )
        end

        def updated_pom_requirement(dependency)
          dependency.
            requirements.
            find { |f| f.fetch(:file) == "pom.xml" }.
            fetch(:requirement)
        end

        def original_pom_requirement(dependency)
          dependency.
            previous_requirements.
            find { |f| f.fetch(:file) == "pom.xml" }.
            fetch(:requirement)
        end

        def pom
          @pom ||= get_original_file("pom.xml")
        end
      end
    end
  end
end
