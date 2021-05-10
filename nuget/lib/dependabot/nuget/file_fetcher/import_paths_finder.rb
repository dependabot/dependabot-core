# frozen_string_literal: true

require "nokogiri"
require "pathname"

require "dependabot/nuget/file_fetcher"

module Dependabot
  module Nuget
    class FileFetcher
      class ImportPathsFinder
        def initialize(project_file:)
          @project_file = project_file
        end

        def import_paths
          doc = Nokogiri::XML(project_file.content)
          doc.remove_namespaces!
          doc.xpath("/Project/Import").map do |import_node|
            path = import_node.attribute("Project").value.strip.tr("\\", "/")
            path = File.join(current_dir, path) unless current_dir.nil?
            Pathname.new(path).cleanpath.to_path
          end
        end

        def project_reference_paths
          doc = Nokogiri::XML(project_file.content)
          doc.remove_namespaces!
          nodes = doc.xpath("/Project/ItemGroup/ProjectReference").map do |node|
            attribute = node.attribute("Include")
            next unless attribute

            path = attribute.value.strip.tr("\\", "/")
            path = File.join(current_dir, path) unless current_dir.nil?
            Pathname.new(path).cleanpath.to_path
          end

          nodes.compact
        end

        private

        attr_reader :project_file

        def current_dir
          current_dir = project_file.name.rpartition("/").first
          current_dir = nil if current_dir == ""
          current_dir
        end
      end
    end
  end
end
