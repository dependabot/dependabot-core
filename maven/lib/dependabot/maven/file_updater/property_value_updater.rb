# frozen_string_literal: true

require "nokogiri"

require "dependabot/dependency_file"
require "dependabot/maven/file_updater"
require "dependabot/maven/file_parser/property_value_finder"

module Dependabot
  module Maven
    class FileUpdater
      class PropertyValueUpdater
        def initialize(dependency_files:)
          @dependency_files = dependency_files
        end

        def update_pomfiles_for_property_change(property_name:, callsite_pom:,
                                                updated_value:)
          declaration_details = property_value_finder.property_details(
            property_name: property_name,
            callsite_pom: callsite_pom
          )
          node = declaration_details.fetch(:node)
          filename = declaration_details.fetch(:file)

          pom_to_update = dependency_files.find { |f| f.name == filename }
          property_re = %r{<#{Regexp.quote(node.name)}>
            \s*#{Regexp.quote(node.content)}\s*
            </#{Regexp.quote(node.name)}>}xm
          property_text = node.to_s
          if pom_to_update.content&.match?(property_re)
            updated_content = pom_to_update.content.sub(
              property_re,
              "<#{node.name}>#{updated_value}</#{node.name}>"
            )
          elsif pom_to_update.content.include? property_text
            node.content = updated_value
            updated_content = pom_to_update.content.sub(
              property_text,
              node.to_s
            )
          end

          updated_pomfiles = dependency_files.dup
          updated_pomfiles[updated_pomfiles.index(pom_to_update)] =
            update_file(file: pom_to_update, content: updated_content)

          updated_pomfiles
        end

        private

        attr_reader :dependency_files

        def property_value_finder
          @property_value_finder ||=
            Maven::FileParser::PropertyValueFinder.
            new(dependency_files: dependency_files)
        end

        def update_file(file:, content:)
          updated_file = file.dup
          updated_file.content = content
          updated_file
        end
      end
    end
  end
end
