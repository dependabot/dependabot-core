# frozen_string_literal: true

require "nokogiri"

require "pathname"
require "dependabot/file_fetchers/dotnet/nuget"

module Dependabot
  module FileFetchers
    module Dotnet
      class Nuget
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

          private

          attr_reader :project_file

          def current_dir
            parts = project_file.name.split("/")[0..-2]
            return if parts.empty?
            parts.join("/")
          end
        end
      end
    end
  end
end
