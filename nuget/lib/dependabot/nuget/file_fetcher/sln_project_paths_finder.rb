# frozen_string_literal: true

require "pathname"
require "dependabot/nuget/file_fetcher"

module Dependabot
  module Nuget
    class FileFetcher
      class SlnProjectPathsFinder
        PROJECT_PATH_REGEX =
          /(?<=["'])[^"']*?\.(?:vb|cs|fs)proj(?=["'])/.freeze

        def initialize(sln_file:)
          @sln_file = sln_file
        end

        def project_paths
          paths = []
          sln_file_lines = sln_file.content.lines

          sln_file_lines.each_with_index do |line, index|
            next unless line.match?(/^\s*Project/)

            # Don't know how to handle multi-line project declarations yet
            next unless sln_file_lines[index + 1]&.match?(/^\s*EndProject/)

            path = line.split('"')[5]
            path = path.tr("\\", "/")

            # If the path doesn't have an extension it's probably a directory
            next unless path.match?(/\.[a-z]{2}proj$/)

            path = File.join(current_dir, path) unless current_dir.nil?
            paths << Pathname.new(path).cleanpath.to_path
          end

          paths
        end

        private

        attr_reader :sln_file

        def current_dir
          parts = sln_file.name.split("/")[0..-2]
          return if parts.empty?

          parts.join("/")
        end
      end
    end
  end
end
