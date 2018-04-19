# frozen_string_literal: true

require "nokogiri"

require "dependabot/dependency"
require "dependabot/file_parsers/base"

module Dependabot
  module FileParsers
    module Java
      class Maven < Dependabot::FileParsers::Base
        require "dependabot/file_parsers/base/dependency_set"

        DEPENDENCY_SELECTOR = "parent, dependencies > dependency,
                               plugins > plugin"
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
          doc.css(DEPENDENCY_SELECTOR).each do |dependency_node|
            next unless dependency_name(dependency_node)
            dependency_set <<
              Dependency.new(
                name: dependency_name(dependency_node),
                version: dependency_version(dependency_node),
                package_manager: "maven",
                requirements: [{
                  requirement: dependency_requirement(dependency_node),
                  file: pom.name,
                  groups: [],
                  source: nil
                }]
              )
          end

          dependency_set
        end

        def dependency_name(dependency_node)
          return unless dependency_node.at_css("groupId")
          return unless dependency_node.at_css("artifactId")

          [
            dependency_node.at_css("groupId").content.strip,
            dependency_node.at_css("artifactId").content.strip
          ].join(":")
        end

        def dependency_version(dependency_node)
          requirement = dependency_requirement(dependency_node)
          return nil unless requirement

          # If a range is specified then we can't tell the exact version
          return nil if requirement.include?(",")

          # Remove brackets if present (and not denoting a range)
          requirement.gsub(/[\(\)\[\]]/, "").strip
        end

        def dependency_requirement(dependency_node)
          return unless dependency_node.at_css("version")
          version_content = dependency_node.at_css("version").content.strip

          return version_content unless version_content.match?(PROPERTY_REGEX)

          prop_name = version_content.match(PROPERTY_REGEX).
                      named_captures.fetch("property")

          property_value = value_for_property(prop_name)
          version_content.gsub(PROPERTY_REGEX, property_value)
        end

        def value_for_property(property_name)
          pomfiles.each do |pom|
            doc = Nokogiri::XML(pom.content)
            doc.remove_namespaces!

            value =
              if property_name.start_with?("project.")
                path = "//project/#{property_name.gsub(/^project\./, '')}"
                doc.at_xpath(path)&.content&.strip ||
                  doc.at_xpath("//properties/#{property_name}")&.content&.strip
              else
                doc.at_xpath("//properties/#{property_name}")&.content&.strip
              end

            return value if value
          end

          raise "Property not found: #{prop_name}"
        end

        def pomfiles
          @pomfiles ||=
            dependency_files.select { |f| f.name.end_with?("pom.xml") }
        end

        def check_required_files
          raise "No pom.xml!" unless get_original_file("pom.xml")
        end
      end
    end
  end
end
