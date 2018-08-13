# frozen_string_literal: true

require "dependabot/file_fetchers/base"
require "dependabot/file_parsers/python/pip"

module Dependabot
  module FileFetchers
    module Python
      class Pip < Dependabot::FileFetchers::Base
        CHILD_REQUIREMENT_REGEX = /^-r\s?(?<path>.*\.txt)/
        CONSTRAINT_REGEX = /^-c\s?(?<path>\..*)/

        def self.required_files_in?(filenames)
          return true if filenames.any? { |name| name.end_with?(".txt") }

          # If there is a directory of requirements return true
          return true if filenames.include?("requirements")

          # If this repo is using a Pipfile return true
          return true if (%w(Pipfile Pipfile.lock) - filenames).empty?

          # If this repo is using Poetry return true
          return true if filenames.include?("pyproject.toml")

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

          fetched_files += pipenv_files
          fetched_files += pyproject_files

          fetched_files += requirement_files if requirements_txt_files.any?
          fetched_files += requirements_in_files

          check_required_files_present
          fetched_files.uniq
        end

        def pipenv_files
          [pipfile, pipfile_lock].compact
        end

        def pyproject_files
          [pyproject, pyproject_lock].compact
        end

        def requirement_files
          [
            *requirements_txt_files,
            *child_requirement_files,
            *constraints_files,
            *path_setup_files
          ]
        end

        def check_required_files_present
          if requirements_txt_files.any? || setup_file ||
             (pipfile && pipfile_lock) || pyproject
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

        def pipfile_lock
          @pipfile_lock ||= fetch_file_if_present("Pipfile.lock")
        end

        def pyproject
          @pyproject ||= fetch_file_if_present("pyproject.toml")
        end

        def pyproject_lock
          @pyproject_lock ||= fetch_file_if_present("pyproject.lock")
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
            select { |f| f.name.end_with?(".txt", ".in") }.
            map { |f| fetch_file_from_host(f.name) }.
            select { |f| requirements_file?(f) }.
            each { |f| @req_txt_and_in_files << f }

          repo_contents.
            select { |f| f.type == "dir" }.
            each { |f| @req_txt_and_in_files += req_files_for_dir(f) }

          @req_txt_and_in_files
        end

        def req_files_for_dir(requirements_dir)
          dir = directory.gsub(%r{(^/|/$)}, "")
          relative_reqs_dir =
            requirements_dir.path.gsub(%r{^/?#{Regexp.escape(dir)}/?}, "")

          repo_contents(dir: relative_reqs_dir).
            select { |f| f.type == "file" }.
            select { |f| f.name.end_with?(".txt", ".in") }.
            map { |f| fetch_file_from_host("#{relative_reqs_dir}/#{f.name}") }.
            select { |f| requirements_file?(f) }
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
          paths = file.content.scan(CHILD_REQUIREMENT_REGEX).flatten
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
            req_file.content.scan(CONSTRAINT_REGEX).flatten
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

        def requirements_file?(file)
          return true if file.name.match?(/requirements/x)

          content = file.content.
                    gsub(CONSTRAINT_REGEX, "").
                    gsub(CHILD_REQUIREMENT_REGEX, "")

          tmp_file = DependencyFile.new(name: file.name, content: content)
          Dependabot::FileParsers::Python::Pip.
            new(dependency_files: [tmp_file], source: source).
            parse.any?
        rescue Dependabot::DependencyFileNotEvaluatable
          false
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
