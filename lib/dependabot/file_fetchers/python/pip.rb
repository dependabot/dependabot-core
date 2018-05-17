# frozen_string_literal: true

require "dependabot/file_fetchers/base"

module Dependabot
  module FileFetchers
    module Python
      class Pip < Dependabot::FileFetchers::Base
        def self.required_files_in?(filenames)
          if filenames.any? { |name| name.match?(/requirements.*\.txt/x) }
            return true
          end

          # If there is a directory of requirements return true
          return true if filenames.include?("requirements")

          # If this repo is using a Pipfile return true
          return true if (%w(Pipfile Pipfile.lock) - filenames).empty?

          filenames.include?("setup.py")
        end

        def self.required_files_message
          "Repo must contain a requirements.txt, setup.py or a Pipfile and " \
          "Pipfile.lock."
        end

        private

        def fetch_files
          fetched_files = []

          fetched_files << setup_file if setup_file
          fetched_files << pip_conf if pip_conf
          fetched_files << pipfile if pipfile
          fetched_files << lockfile if lockfile

          if requirements_txt_files.any?
            fetched_files += requirements_txt_files
            fetched_files += child_requirement_files
            fetched_files += constraints_files
            fetched_files += path_setup_files
          end

          fetched_files += requirements_in_files

          check_required_files_present
          fetched_files.uniq
        end

        def check_required_files_present
          if requirements_txt_files.any? || setup_file || (pipfile && lockfile)
            return
          end

          path = Pathname.new(File.join(directory, "requirements.txt")).
                 cleanpath.to_path
          raise Dependabot::DependencyFileNotFound, path
        end

        def setup_file
          @setup_file ||= fetch_file_if_present("setup.py")
        end

        def pip_conf
          @pip_conf ||= fetch_file_if_present("pip.conf")
        end

        def pipfile
          @pipfile ||= fetch_file_if_present("Pipfile")
        end

        def lockfile
          @lockfile ||= fetch_file_if_present("Pipfile.lock")
        end

        def requirements_txt_files
          req_txt_and_in_files.select { |f| f.name.end_with?(".txt") }
        end

        def requirements_in_files
          req_txt_and_in_files.select { |f| f.name.end_with?(".in") }
        end

        def req_txt_and_in_files
          return @req_txt_and_in_files if @req_txt_and_in_files
          @req_txt_and_in_files = []

          repo_contents.
            select { |f| f.type == "file" }.
            select { |f| f.name.match?(/requirements/x) }.
            select { |f| f.name.end_with?(".txt", ".in") }.
            each { |f| @req_txt_and_in_files << fetch_file_from_host(f.name) }

          @req_txt_and_in_files += requirements_directory_files
          @req_txt_and_in_files
        end

        def requirements_directory_files
          requirements_directory =
            repo_contents.find do |file|
              file.type == "dir" && file.name == "requirements"
            end

          return [] unless requirements_directory

          dir = directory.gsub(%r{(^/|/$)}, "")
          relative_requirements_directory =
            requirements_directory.path.gsub(%r{^/?#{Regexp.escape(dir)}/?}, "")

          repo_contents(dir: relative_requirements_directory).
            select { |f| f.type == "file" }.
            select { |f| f.name.end_with?(".txt", ".in") }.
            map { |f| fetch_file_from_host("requirements/#{f.name}") }
        end

        def child_requirement_files
          @child_requirement_files ||=
            requirements_txt_files.flat_map do |requirement_file|
              fetch_child_requirement_files(
                file: requirement_file,
                previously_fetched_files: []
              )
            end
        end

        def fetch_child_requirement_files(file:, previously_fetched_files:)
          paths = file.content.scan(/^-r\s?(?<path>.*\.txt)/).flatten
          current_dir = file.name.split("/")[0..-2].last

          paths.flat_map do |path|
            path = File.join(current_dir, path) unless current_dir.nil?
            path = Pathname.new(path).cleanpath.to_path

            next if previously_fetched_files.map(&:name).include?(path)
            next if file.name == path

            fetched_file = fetch_file_from_host(path)
            grandchild_requirement_files = fetch_child_requirement_files(
              file: fetched_file,
              previously_fetched_files: previously_fetched_files + [file]
            )
            [fetched_file, *grandchild_requirement_files]
          end.compact
        end

        def constraints_files
          all_requirement_files = requirements_txt_files +
                                  child_requirement_files

          constraints_paths = all_requirement_files.map do |req_file|
            req_file.content.scan(/^-c\s?(?<path>\..*)/).flatten
          end.flatten.uniq

          constraints_paths.map { |path| fetch_file_from_host(path) }
        end

        def path_setup_files
          path_setup_files = []
          unfetchable_files = []

          path_setup_file_paths.each do |path|
            path = Pathname.new(File.join(path, "setup.py")).cleanpath.to_path
            next if path == "setup.py" && setup_file
            path_setup_files << fetch_file_from_host(path)
          rescue Dependabot::DependencyFileNotFound
            unfetchable_files << path
          end

          if unfetchable_files.any?
            raise Dependabot::PathDependenciesNotReachable, unfetchable_files
          end

          path_setup_files
        end

        def path_setup_file_paths
          (requirements_txt_files + child_requirement_files).map do |req_file|
            req_file.content.scan(/^(?:-e\s)?(?<path>\..*?)(?=\[|#|$)/).flatten
          end.flatten
        end
      end
    end
  end
end
