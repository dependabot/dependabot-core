# frozen_string_literal: true
require "dependabot/file_fetchers/base"

module Dependabot
  module FileFetchers
    module Python
      class Pip < Dependabot::FileFetchers::Base
        def self.required_files
          %w(requirements.txt)
        end

        private

        def extra_files
          fetched_files = []
          fetched_files += child_requirement_files
          fetched_files += setup_files
          fetched_files
        end

        def child_requirement_files
          @child_requirement_files ||=
            recursively_fetch_child_requirement_files(requirement_file)
        end

        def recursively_fetch_child_requirement_files(file, fetched_files = [])
          paths = file.content.scan(/^-r\s?(?<path>\..*)/).flatten
          files = []

          paths.each do |path|
            path = Pathname.new(path).cleanpath.to_path
            next if fetched_files.map(&:name).include?(path)
            fetched_file = fetch_file_from_github(path)
            files << fetched_file
            files += recursively_fetch_child_requirement_files(
              fetched_file,
              files
            )
          end

          files
        end

        def setup_files
          setup_files = []
          unfetchable_files = []

          setup_file_paths.each do |path|
            begin
              path = Pathname.new(File.join(path, "setup.py")).cleanpath.to_path
              setup_files << fetch_file_from_github(path)
            rescue Dependabot::DependencyFileNotFound
              unfetchable_files << path
            end
          end

          if unfetchable_files.any?
            raise Dependabot::PathDependenciesNotReachable, unfetchable_files
          end

          setup_files
        end

        def setup_file_paths
          ([requirement_file] + child_requirement_files).map do |req_file|
            req_file.content.scan(/^(?:-e\s)?(?<path>\..*)/).flatten
          end.flatten
        end

        def requirement_file
          @requirements_file ||=
            required_files.find { |f| f.name == "requirements.txt" }
        end
      end
    end
  end
end
