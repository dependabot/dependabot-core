# frozen_string_literal: true

require "nokogiri"

require "dependabot/file_parsers/java/maven"

# For documentation, see the "Available Variables" section of
# http://maven.apache.org/guides/introduction/introduction-to-the-pom.html
module Dependabot
  module FileParsers
    module Java
      class Maven
        class PropertyValueFinder
          def initialize(dependency_files:)
            @dependency_files = dependency_files
          end

          def property_value(property_name:, callsite_pom:)
            pom = dependency_files.find { |f| f.name == callsite_pom.name }

            doc = Nokogiri::XML(pom.content)
            doc.remove_namespaces!

            # Loop through the paths that would satisfy this property name,
            # looking for one that exists in this POM
            temp_name = sanitize_property_name(property_name)
            property_value =
              loop do
                node =
                  doc.at_xpath("//#{temp_name}") ||
                  doc.at_xpath("//properties/#{temp_name}")
                break node.content.strip if node
                break unless temp_name.include?(".")
                temp_name = temp_name.sub(".", "/")
              end

            # If we found a property, return it
            return property_value if property_value

            # Otherwise, look for a value in this pom's parent
            return unless (parent = parent_pom(pom))
            property_value(
              property_name: property_name,
              callsite_pom: parent
            )
          end

          private

          attr_reader :dependency_files

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
