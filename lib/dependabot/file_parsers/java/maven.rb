# frozen_string_literal: true

require "nokogiri"

require "dependabot/dependency"
require "dependabot/file_parsers/base"

module Dependabot
  module FileParsers
    module Java
      class Maven < Dependabot::FileParsers::Base
        def parse
          doc = Nokogiri::XML(pom.content)
          doc.css("dependencies dependency").map do |dependency_node|
            Dependency.new(
              name: dependency_name(dependency_node),
              version: dependency_version(dependency_node),
              package_manager: "maven",
              requirements: [{
                requirement: dependency_version(dependency_node),
                file: "pom.xml",
                groups: [],
                source: nil
              }]
            )
          end
        end

        private

        def dependency_name(dependency_node)
          [
            dependency_node.at_css("groupId").content,
            dependency_node.at_css("artifactId").content
          ].join(":")
        end

        def dependency_version(dependency_node)
          version_content = dependency_node.at_css("version").content

          return version_content unless version_content.start_with?("${")

          property_name = version_content.strip[2..-2]
          doc = Nokogiri::XML(pom.content)
          doc.remove_namespaces!
          doc.at_xpath("//properties/#{property_name}").content
        end

        def pom
          @pom ||= get_original_file("pom.xml")
        end

        def check_required_files
          %w(pom.xml).each do |filename|
            raise "No #{filename}!" unless get_original_file(filename)
          end
        end
      end
    end
  end
end
