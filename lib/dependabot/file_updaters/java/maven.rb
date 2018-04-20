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
            dependencies.reduce(pom.content.dup) do |content, dep|
              if updating_a_property?(dep)
                content = update_property_version(dep)
                remove_property_version_suffix(dep, content)
              else
                content.gsub(
                  original_pom_declaration(dep),
                  updated_pom_declaration(dep)
                )
              end
            end

          raise "Expected content to change!" if updated_content == pom.content
          updated_content
        end

        def update_property_version(dependency)
          declaration_node = Nokogiri::XML(original_pom_declaration(dependency))
          prop_name =
            declaration_node.at_css("version").content.strip.
            match(FileParsers::Java::Maven::PROPERTY_REGEX).
            named_captures["property"]
          suffix =
            declaration_node.at_css("version").content.strip.
            match(/\$\{(?<property>.*?)\}(?<suffix>.*)/).
            named_captures["suffix"]

          original_requirement = original_pom_requirement(dependency)
          if suffix
            original_requirement =
              original_requirement.gsub(/#{Regexp.quote(suffix)}$/, "")
          end
          updated_requirement = updated_pom_requirement(dependency)

          pom.content.gsub(
            "<#{prop_name}>#{original_requirement}</#{prop_name}>",
            "<#{prop_name}>#{updated_requirement}</#{prop_name}>"
          )
        end

        def remove_property_version_suffix(dep, content)
          content.gsub(original_pom_declaration(dep)) do |original_declaration|
            version_string =
              original_declaration.match(%r{(?<=\<version\>).*(?=\</version\>)})
            cleaned_version_string = version_string.to_s.gsub(/(?<=\}).*/, "")

            original_declaration.gsub(
              "<version>#{version_string}</version>",
              "<version>#{cleaned_version_string}</version>"
            )
          end
        end

        def updating_a_property?(dependency)
          DeclarationFinder.new(
            dependency: dependency,
            declaring_requirement: dependency.previous_requirements.first,
            dependency_files: dependency_files
          ).version_comes_from_property?
        end

        def original_pom_declaration(dependency)
          DeclarationFinder.new(
            dependency: dependency,
            declaring_requirement: dependency.previous_requirements.first,
            dependency_files: dependency_files
          ).declaration_string
        end

        def updated_pom_declaration(dependency)
          original_requirement = original_pom_requirement(dependency)
          original_pom_declaration(dependency).gsub(
            %r{<version>\s*#{Regexp.quote(original_requirement)}\s*</version>},
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
