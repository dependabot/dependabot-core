# typed: true
# frozen_string_literal: true

require "pathname"
require "dependabot/nuget/file_fetcher"

module Dependabot
  module Nuget
    class FileFetcher
      class SlnProjectPathsFinder
        def initialize(sln_file:)
          @sln_file = sln_file
        end

        def project_paths
          paths = []
          sln_file_lines = sln_file.content.lines

          sln_file_lines.each do |line|
            next unless line.match?(/^\s*Project\(/)
            next unless line.split('"')[5]

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
          current_dir = sln_file.name.rpartition("/").first
          current_dir = nil if current_dir == ""
          current_dir
        end
      end
    end
  end
end
