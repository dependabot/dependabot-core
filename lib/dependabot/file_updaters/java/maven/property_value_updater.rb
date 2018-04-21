# frozen_string_literal: true

require "nokogiri"

require "dependabot/dependency_file"
require "dependabot/file_updaters/java/maven"
require "dependabot/file_parsers/java/maven/property_value_finder"

module Dependabot
  module FileUpdaters
    module Java
      class Maven
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
            updated_content = pom_to_update.content.gsub(
              %r{<#{Regexp.quote(node.name)}>.*</#{Regexp.quote(node.name)}>},
              "<#{node.name}>#{updated_value}</#{node.name}>"
            )

            updated_pomfiles = dependency_files.dup
            updated_pomfiles[updated_pomfiles.index(pom_to_update)] =
              Dependabot::DependencyFile.new(
                name: pom_to_update.name,
                content: updated_content
              )

            updated_pomfiles
          end

          private

          attr_reader :dependency_files

          def property_value_finder
            @property_value_finder ||=
              FileParsers::Java::Maven::PropertyValueFinder.new(
                dependency_files: dependency_files
              )
          end
        end
      end
    end
  end
end
