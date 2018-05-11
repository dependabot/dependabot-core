# frozen_string_literal: true

require "nokogiri"

require "dependabot/dependency_file"
require "dependabot/file_parsers/java/maven"
require "dependabot/shared_helpers"

# For documentation, see:
# - http://maven.apache.org/guides/introduction/introduction-to-the-pom.html
# - http://maven.apache.org/pom.html#Properties
module Dependabot
  module FileParsers
    module Java
      class Maven
        class PropertyValueFinder
          require_relative "repositories_finder"

          def initialize(dependency_files:)
            @dependency_files = dependency_files
          end

          def property_details(property_name:, callsite_pom:)
            pom = callsite_pom
            doc = Nokogiri::XML(pom.content)
            doc.remove_namespaces!

            # Loop through the paths that would satisfy this property name,
            # looking for one that exists in this POM
            nm = sanitize_property_name(property_name)
            node =
              loop do
                candidate_node =
                  doc.at_xpath("/project/#{nm}") ||
                  doc.at_xpath("/project/properties/#{nm}") ||
                  doc.at_xpath("/project/profiles/profile/properties/#{nm}")
                break candidate_node if candidate_node
                break unless nm.include?(".")
                nm = nm.sub(".", "/")
              end

            # If we found a property, return it
            if node
              return { file: pom.name, node: node, value: node.content.strip }
            end

            # Otherwise, look for a value in this pom's parent
            return unless (parent = parent_pom(pom))
            property_details(
              property_name: property_name,
              callsite_pom: parent
            )
          end

          private

          attr_reader :dependency_files

          def internal_dependency_poms
            return @internal_dependency_poms if @internal_dependency_poms

            @internal_dependency_poms = {}
            dependency_files.each do |pom|
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
            group_id = doc.at_xpath("/project/parent/groupId")&.content&.strip
            artifact_id =
              doc.at_xpath("/project/parent/artifactId")&.content&.strip
            version = doc.at_xpath("/project/parent/version")&.content&.strip

            return unless group_id && artifact_id
            name = [group_id, artifact_id].join(":")

            if internal_dependency_poms[name]
              return internal_dependency_poms[name]
            end

            fetch_remote_parent_pom(group_id, artifact_id, version, pom)
          end

          def parent_repository_urls(pom)
            repositories_finder.repository_urls(
              pom: pom,
              exclude_inherited: true
            )
          end

          def repositories_finder
            @repositories_finder ||=
              RepositoriesFinder.new(dependency_files: dependency_files)
          end

          def fetch_remote_parent_pom(group_id, artifact_id, version, pom)
            parent_repository_urls(pom).each do |base_url|
              url = remote_pom_url(group_id, artifact_id, version, base_url)

              @maven_responses ||= {}
              @maven_responses[url] ||= Excon.get(
                url,
                idempotent: true,
                omit_default_port: true,
                middlewares: SharedHelpers.excon_middleware
              )
              next unless @maven_responses[url].status == 200
              next unless pom?(@maven_responses[url].body)

              dependency_file = DependencyFile.new(
                name: "remote_pom.xml",
                content: @maven_responses[url].body
              )

              return dependency_file
            end

            # If a parent POM couldn't be found, return `nil`
            nil
          end

          def remote_pom_url(group_id, artifact_id, version, base_repo_url)
            "#{base_repo_url}/"\
            "#{group_id.tr('.', '/')}/#{artifact_id}/#{version}/"\
            "#{artifact_id}-#{version}.pom"
          end

          def pom?(content)
            !Nokogiri::XML(content).at_css("project > artifactId").nil?
          end
        end
      end
    end
  end
end
