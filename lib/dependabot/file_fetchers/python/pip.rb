# frozen_string_literal: true

require "dependabot/file_fetchers/base"

module Dependabot
  module FileFetchers
    module Python
      class Pip < Dependabot::FileFetchers::Base
        def self.required_files_in?(filenames)
          filenames.include?("requirements.txt")
        end

        def self.required_files_message
          "Repo must contain a requirements.txt."
        end

        private

        def fetch_files
          fetched_files = []
          fetched_files << requirement_file
          fetched_files << setup_file unless setup_file.nil?
          fetched_files += child_requirement_files
          fetched_files += constraints_files
          fetched_files += path_setup_files
          fetched_files
        end

        def requirement_file
          @requirements_file ||= fetch_file_from_github("requirements.txt")
        end

        def setup_file
          @setup_file ||= fetch_file_from_github("setup.py")
        rescue Dependabot::DependencyFileNotFound
          nil
        end

        def child_requirement_files
          @child_requirement_files ||=
            recursively_fetch_child_requirement_files(
              requirement_file,
              [requirement_file]
            )
        end

        def recursively_fetch_child_requirement_files(file, fetched_files = [])
          paths = file.content.scan(/^-r\s?(?<path>.*\.txt)/).flatten
          current_dir = file.name.split("/")[0..-2].last
          files = []

          paths.each do |path|
            path = File.join(current_dir, path) unless current_dir.nil?
            path = Pathname.new(path).cleanpath.to_path
            next if (files | fetched_files).map(&:name).include?(path)
            fetched_file = fetch_file_from_github(path)
            files << fetched_file
            files += recursively_fetch_child_requirement_files(
              fetched_file,
              files
            )
          end

          files
        end

        def constraints_files
          all_requirement_files = [requirement_file] + child_requirement_files

          constraints_paths = all_requirement_files.map do |req_file|
            req_file.content.scan(/^-c\s?(?<path>\..*)/).flatten
          end.flatten.uniq

          constraints_paths.map { |path| fetch_file_from_github(path) }
        end

        def path_setup_files
          path_setup_files = []
          unfetchable_files = []

          path_setup_file_paths.each do |path|
            begin
              path = Pathname.new(File.join(path, "setup.py")).cleanpath.to_path
              next if path == "setup.py" && setup_file
              path_setup_files << fetch_file_from_github(path)
            rescue Dependabot::DependencyFileNotFound
              unfetchable_files << path
            end
          end

          if unfetchable_files.any?
            raise Dependabot::PathDependenciesNotReachable, unfetchable_files
          end

          path_setup_files
        end

        def path_setup_file_paths
          ([requirement_file] + child_requirement_files).map do |req_file|
            req_file.content.scan(/^(?:-e\s)?(?<path>\..*)/).flatten
          end.flatten
        end
      end
    end
  end
end
