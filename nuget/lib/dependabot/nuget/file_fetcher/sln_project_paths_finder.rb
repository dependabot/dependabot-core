# typed: strict
# frozen_string_literal: true

require "pathname"
require "dependabot/nuget/file_fetcher"

module Dependabot
  module Nuget
    class FileFetcher
      class SlnProjectPathsFinder
        extend T::Sig

        sig { params(sln_file: Dependabot::DependencyFile).void }
        def initialize(sln_file:)
          @sln_file = sln_file
        end

        sig { returns(T::Array[String]) }
        def project_paths
          paths = T.let([], T::Array[String])
          return paths unless sln_file.content

          sln_file_lines = T.must(sln_file.content).lines

          sln_file_lines.each do |line|
            next unless line.match?(/^\s*Project\(/)
            next unless line.split('"')[5]

            path = line.split('"')[5]
            next unless path

            path = path.tr("\\", "/")

            # If the path doesn't have an extension it's probably a directory
            next unless path.match?(/\.[a-z]{2}proj$/)

            path = File.join(current_dir, path) unless current_dir.nil?
            paths << Pathname.new(path).cleanpath.to_path
          end

          paths
        end

        private

        sig { returns(Dependabot::DependencyFile) }
        attr_reader :sln_file

        sig { returns(T.nilable(String)) }
        def current_dir
          current_dir = sln_file.name.rpartition("/").first
          current_dir = nil if current_dir == ""
          current_dir
        end
      end
    end
  end
end
