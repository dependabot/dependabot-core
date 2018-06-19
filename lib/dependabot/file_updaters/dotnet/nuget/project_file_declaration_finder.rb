# frozen_string_literal: true

require "nokogiri"
require "dependabot/file_updaters/dotnet/nuget"

module Dependabot
  module FileUpdaters
    module Dotnet
      class Nuget
        class ProjectFileDeclarationFinder
          DECLARATION_REGEX =
            %r{<PackageReference [^>]*?/>|
               <PackageReference [^>]*?[^/]>.*?</PackageReference>}mx

          attr_reader :dependency_name, :declaring_requirement,
                      :dependency_files

          def initialize(dependency_name:, dependency_files:,
                         declaring_requirement:)
            @dependency_name       = dependency_name
            @dependency_files      = dependency_files
            @declaring_requirement = declaring_requirement
          end

          def declaration_strings
            @declaration_strings ||= fetch_declaration_strings
          end

          def declaration_nodes
            declaration_strings.map do |declaration_string|
              Nokogiri::XML(declaration_string)
            end
          end

          private

          def fetch_declaration_strings
            deep_find_declarations(declaring_file.content).select do |nd|
              node = Nokogiri::XML(nd)
              node.remove_namespaces!
              node = node.at_xpath("/PackageReference")

              node_name = node.attribute("Include")&.value&.strip ||
                          node.at_xpath("./Include")&.content&.strip
              next false unless node_name == dependency_name

              node_requirement = node.attribute("Version")&.value&.strip ||
                                 node.at_xpath("./Version")&.content&.strip
              node_requirement == declaring_requirement.fetch(:requirement)
            end
          end

          def deep_find_declarations(string)
            string.scan(DECLARATION_REGEX).flat_map do |matching_node|
              [matching_node, *deep_find_declarations(matching_node[0..-2])]
            end
          end

          def declaring_file
            filename = declaring_requirement.fetch(:file)
            declaring_file = dependency_files.find { |f| f.name == filename }
            return declaring_file if declaring_file
            raise "No file found with name #{filename}!"
          end
        end
      end
    end
  end
end
