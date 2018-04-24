# frozen_string_literal: true

require "nokogiri"

require "dependabot/dependency"
require "dependabot/file_parsers/base"

# The best Maven documentation is at:
# - http://maven.apache.org/pom.html
module Dependabot
  module FileParsers
    module Java
      class Maven < Dependabot::FileParsers::Base
        require "dependabot/file_parsers/base/dependency_set"
        require_relative "maven/property_value_finder"

        # The following "dependencies" are candidates for updating:
        # - The project's parent
        # - Any dependencies (incl. those in dependencyManagement or plugins)
        # - Any plugins (incl. those in pluginManagement)
        # - Any extensions
        DEPENDENCY_SELECTOR = "project > parent, "\
                              "dependencies > dependency, "\
                              "plugins > plugin, "\
                              "extensions > extension"\

        # Regex to get the property name from a declaration that uses a property
        PROPERTY_REGEX      = /\$\{(?<property>.*?)\}/

        def parse
          dependency_set = DependencySet.new
          pomfiles.each { |pom| dependency_set += pomfile_dependencies(pom) }
          dependency_set.dependencies
        end

        private

        def pomfile_dependencies(pom)
          dependency_set = DependencySet.new

          doc = Nokogiri::XML(pom.content)
          doc.remove_namespaces!
          doc.css(DEPENDENCY_SELECTOR).each do |dependency_node|
            next unless (name = dependency_name(dependency_node, pom))
            next if internal_dependency_names.include?(name)
            property = version_property_name(dependency_node)

            dependency_set <<
              Dependency.new(
                name: name,
                version: dependency_version(pom, dependency_node),
                package_manager: "maven",
                requirements: [{
                  requirement: dependency_requirement(pom, dependency_node),
                  file: pom.name,
                  groups: [],
                  source: nil,
                  metadata: property ? { property_name: property } : nil
                }]
              )
          end

          dependency_set
        end

        def dependency_name(dependency_node, pom)
          return unless dependency_node.at_xpath("./groupId")
          return unless dependency_node.at_xpath("./artifactId")

          [
            evaluated_value(
              dependency_node.at_xpath("./groupId").content.strip,
              pom
            ),
            evaluated_value(
              dependency_node.at_xpath("./artifactId").content.strip,
              pom
            )
          ].join(":")
        end

        def dependency_version(pom, dependency_node)
          requirement = dependency_requirement(pom, dependency_node)
          return nil unless requirement

          # If a range is specified then we can't tell the exact version
          return nil if requirement.include?(",")

          # Remove brackets if present (and not denoting a range)
          requirement.gsub(/[\(\)\[\]]/, "").strip
        end

        def dependency_requirement(pom, dependency_node)
          return unless dependency_node.at_xpath("./version")
          version_content = dependency_node.at_xpath("./version").content.strip

          evaluated_value(version_content, pom)
        end

        def version_property_name(dependency_node)
          return unless dependency_node.at_xpath("./version")
          version_content = dependency_node.at_xpath("./version").content.strip

          return unless version_content.match?(PROPERTY_REGEX)

          version_content.
            match(PROPERTY_REGEX).
            named_captures.fetch("property")
        end

        def evaluated_value(value, pom)
          return value unless value.match?(PROPERTY_REGEX)

          property_name = value.match(PROPERTY_REGEX).
                          named_captures.fetch("property")
          property_value = value_for_property(property_name, pom)

          value.gsub(PROPERTY_REGEX, property_value)
        end

        def value_for_property(property_name, pom)
          value =
            property_value_finder.
            property_details(property_name: property_name, callsite_pom: pom)&.
            fetch(:value)

          raise "Property not found: #{property_name}" unless value
          value
        end

        # Cached, since this can makes calls to the registry (to get property
        # values from parent POMs)
        def property_value_finder
          @property_value_finder ||=
            PropertyValueFinder.new(dependency_files: dependency_files)
        end

        def pomfiles
          # Note: this (correctly) excludes any parent POMs that were downloaded
          @pomfiles ||=
            dependency_files.select { |f| f.name.end_with?("pom.xml") }
        end

        def internal_dependency_names
          @internal_dependency_names ||=
            dependency_files.map do |pom|
              doc = Nokogiri::XML(pom.content)
              group_id    = doc.at_css("project > groupId") ||
                            doc.at_css("project > parent > groupId")
              artifact_id = doc.at_css("project > artifactId")

              next unless group_id && artifact_id

              [group_id.content.strip, artifact_id.content.strip].join(":")
            end.compact
        end

        def check_required_files
          raise "No pom.xml!" unless get_original_file("pom.xml")
        end
      end
    end
  end
end
