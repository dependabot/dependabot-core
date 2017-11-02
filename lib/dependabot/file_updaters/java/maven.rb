# frozen_string_literal: true

require "nokogiri"
require "dependabot/file_updaters/base"

module Dependabot
  module FileUpdaters
    module Java
      class Maven < Dependabot::FileUpdaters::Base
        def self.updated_files_regex
          [/^pom\.xml$/]
        end

        def updated_dependency_files
          [updated_file(file: pom, content: updated_pom_content)]
        end

        private

        def check_required_files
          %w(pom.xml).each do |filename|
            raise "No #{filename}!" unless get_original_file(filename)
          end
        end

        def updated_pom_content
          doc = Nokogiri::XML(pom.content)
          original_node = doc.css("dependencies dependency").find do |node|
            node_name = [
              node.at_css("groupId").content,
              node.at_css("artifactId").content
            ].join("/")
            node_name == dependency.name
          end

          original_node.at_css("version").content = dependency.version
          doc.to_xml
        end

        def pom
          @pom ||= get_original_file("pom.xml")
        end
      end
    end
  end
end
