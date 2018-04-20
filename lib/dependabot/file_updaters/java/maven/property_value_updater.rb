# frozen_string_literal: true

require "nokogiri"

require "dependabot/dependency_file"
require "dependabot/file_updaters/java/maven"

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
            declaration_details = property_declaration_details(
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

          def property_declaration_details(property_name:, callsite_pom:)
            pom = dependency_files.find { |f| f.name == callsite_pom.name }

            doc = Nokogiri::XML(pom.content)
            doc.remove_namespaces!

            # Loop through the paths that would satisfy this property name,
            # looking for one that exists in this POM
            temp_name = sanitize_property_name(property_name)
            property_node =
              loop do
                node =
                  doc.at_xpath("//#{temp_name}") ||
                  doc.at_xpath("//properties/#{temp_name}")
                break node if node
                break unless temp_name.include?(".")
                temp_name = temp_name.sub(".", "/")
              end

            # If we found a property, return it
            return { file: pom.name, node: property_node } if property_node

            # Otherwise, look for a value in this pom's parent
            return unless (parent = parent_pom(pom))
            property_declaration_details(
              property_name: property_name,
              callsite_pom: parent
            )
          end

          def pomfiles
            @pomfiles ||=
              dependency_files.select { |f| f.name.end_with?("pom.xml") }
          end

          def internal_dependency_poms
            return @internal_dependency_poms if @internal_dependency_poms

            @internal_dependency_poms = {}
            pomfiles.each do |pom|
              doc = Nokogiri::XML(pom.content)
              group_id    = doc.at_css("project > groupId") ||
                            doc.at_css("project > parent > groupId")
              artifact_id = doc.at_css("project > artifactId")

              next unless group_id && artifact_id

              dependency_name = [
                group_id.content.strip,
                artifact_id.content.strip
              ].join(":")

              @internal_dependency_poms[dependency_name] = pom
            end

            @internal_dependency_poms
          end

          def sanitize_property_name(property_name)
            property_name.sub(/^pom\./, "").sub(/^project\./, "")
          end

          def parent_pom(pom)
            doc = Nokogiri::XML(pom.content)
            doc.remove_namespaces!
            group_id = doc.at_xpath("//parent/groupId")
            artifact_id = doc.at_xpath("//parent/artifactId")

            return unless group_id && artifact_id
            name = [group_id.content.strip, artifact_id.content.strip].join(":")
            internal_dependency_poms[name]
          end
        end
      end
    end
  end
end
