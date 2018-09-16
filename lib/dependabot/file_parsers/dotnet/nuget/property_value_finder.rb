# frozen_string_literal: true

require "dependabot/file_parsers/dotnet/nuget"

module Dependabot
  module FileParsers
    module Dotnet
      class Nuget
        class PropertyValueFinder
          def initialize(project_file:)
            @project_file = project_file
          end

          def property_details(property_name:)
            doc = Nokogiri::XML(project_file.content)
            doc.remove_namespaces!

            node = doc.at_xpath("/Project/PropertyGroup/#{property_name}")
            return unless node

            { file: project_file.name, node: node, value: node.content.strip }
          end

          private

          attr_reader :project_file
        end
      end
    end
  end
end
