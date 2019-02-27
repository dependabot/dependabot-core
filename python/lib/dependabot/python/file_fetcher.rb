# frozen_string_literal: true

require "toml-rb"

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"
require "dependabot/python/file_parser"
require "dependabot/errors"

# rubocop:disable Metrics/ClassLength
module Dependabot
  module Python
    class FileFetcher < Dependabot::FileFetchers::Base
      CHILD_REQUIREMENT_REGEX = /^-r\s?(?<path>.*\.(?:txt|in))/.freeze
      CONSTRAINT_REGEX = /^-c\s?(?<path>\..*)/.freeze

      def self.required_files_in?(filenames)
        return true if filenames.any? { |name| name.end_with?(".txt", ".in") }

        # If there is a directory of requirements return true
        return true if filenames.include?("requirements")

        # If this repo is using a Pipfile return true
        return true if filenames.include?("Pipfile")

        # If this repo is using Poetry return true
        return true if filenames.include?("pyproject.toml")

        filenames.include?("setup.py")
      end

      def self.required_files_message
        "Repo must contain a requirements.txt, setup.py, pyproject.toml, "\
        "or a Pipfile."
      end

      private

      def fetch_files
        fetched_files = []

        fetched_files += pipenv_files
        fetched_files += pyproject_files

        fetched_files += requirements_in_files
        fetched_files += requirement_files if requirements_txt_files.any?

        fetched_files << setup_file if setup_file
        fetched_files << setup_cfg if setup_cfg
        fetched_files += path_setup_files
        fetched_files << pip_conf if pip_conf
        fetched_files << python_version if python_version

        check_required_files_present
        uniq_files(fetched_files)
      end

      def uniq_files(fetched_files)
        uniq_files = fetched_files.reject(&:support_file?).uniq
        uniq_files += fetched_files.
                      reject { |f| uniq_files.map(&:name).include?(f.name) }
      end

      def pipenv_files
        [pipfile, pipfile_lock].compact
      end

      def pyproject_files
        [pyproject, pyproject_lock, poetry_lock].compact
      end

      def requirement_files
        [
          *requirements_txt_files,
          *child_requirement_txt_files,
          *constraints_files
        ]
      end

      def check_required_files_present
        if requirements_txt_files.any? || setup_file || pipfile || pyproject
          return
        end

        path = Pathname.new(File.join(directory, "requirements.txt")).
               cleanpath.to_path
        raise Dependabot::DependencyFileNotFound, path
      end

      def setup_file
        @setup_file ||= fetch_file_if_present("setup.py")
      end

      def setup_cfg
        @setup_cfg ||= fetch_file_if_present("setup.cfg")
      end

      def pip_conf
        @pip_conf ||= fetch_file_if_present("pip.conf")&.
                      tap { |f| f.support_file = true }
      end

      def python_version
        @python_version ||= fetch_file_if_present(".python-version")&.
                            tap { |f| f.support_file = true }
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

      def poetry_lock
        @poetry_lock ||= fetch_file_if_present("poetry.lock")
      end

      def requirements_txt_files
        req_txt_and_in_files.select { |f| f.name.end_with?(".txt") }
      end

      def requirements_in_files
        req_txt_and_in_files.select { |f| f.name.end_with?(".in") } +
          child_requirement_in_files
      end

      def parsed_pipfile
        raise "No Pipfile" unless pipfile

        @parsed_pipfile ||= TomlRB.parse(pipfile.content)
      rescue TomlRB::ParseError, TomlRB::ValueOverwriteError
        raise Dependabot::DependencyFileNotParseable, pipfile.path
      end

      def parsed_pyproject
        raise "No pyproject.toml" unless pyproject

        @parsed_pyproject ||= TomlRB.parse(pyproject.content)
      rescue TomlRB::ParseError, TomlRB::ValueOverwriteError
        raise Dependabot::DependencyFileNotParseable, pyproject.path
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

      def child_requirement_txt_files
        child_requirement_files.select { |f| f.name.end_with?(".txt") }
      end

      def child_requirement_in_files
        child_requirement_files.select { |f| f.name.end_with?(".in") }
      end

      def child_requirement_files
        @child_requirement_files ||=
          begin
            fetched_files = req_txt_and_in_files.dup
            req_txt_and_in_files.flat_map do |requirement_file|
              child_files = fetch_child_requirement_files(
                file: requirement_file,
                previously_fetched_files: fetched_files
              )

              fetched_files += child_files
              child_files
            end
          end
      end

      def fetch_child_requirement_files(file:, previously_fetched_files:)
        paths = file.content.scan(CHILD_REQUIREMENT_REGEX).flatten
        current_dir = File.dirname(file.name)

        paths.flat_map do |path|
          path = File.join(current_dir, path) unless current_dir == "."
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
                                child_requirement_txt_files

        constraints_paths = all_requirement_files.map do |req_file|
          req_file.content.scan(CONSTRAINT_REGEX).flatten
        end.flatten.uniq

        constraints_paths.map { |path| fetch_file_from_host(path) }
      end

      def path_setup_files
        path_setup_files = []
        unfetchable_files = []

        path_setup_file_paths.each do |path|
          path_setup_files += fetch_path_setup_file(path)
        rescue Dependabot::DependencyFileNotFound => error
          unfetchable_files << error.file_path.gsub(%r{^/}, "")
        end

        poetry_path_setup_file_paths.each do |path|
          path_setup_files += fetch_path_setup_file(path, allow_pyproject: true)
        rescue Dependabot::DependencyFileNotFound => error
          unfetchable_files << error.file_path.gsub(%r{^/}, "")
        end

        if unfetchable_files.any?
          raise Dependabot::PathDependenciesNotReachable, unfetchable_files
        end

        path_setup_files
      end

      def fetch_path_setup_file(path, allow_pyproject: false)
        path_setup_files = []

        unless path.end_with?(".tar.gz", ".zip", ".whl")
          path = Pathname.new(File.join(path, "setup.py")).cleanpath.to_path
        end
        return [] if path == "setup.py" && setup_file

        path_setup_files <<
          begin
            fetch_file_from_host(
              path,
              fetch_submodules: true
            ).tap { |f| f.support_file = true }
          rescue Dependabot::DependencyFileNotFound
            raise unless allow_pyproject

            fetch_file_from_host(
              path.gsub("setup.py", "pyproject.toml"),
              fetch_submodules: true
            ).tap { |f| f.support_file = true }
          end

        return path_setup_files unless path.end_with?(".py")

        path_setup_files + cfg_files_for_setup_py(path)
      end

      def cfg_files_for_setup_py(path)
        cfg_path = path.gsub(/\.py$/, ".cfg")

        begin
          [
            fetch_file_from_host(cfg_path, fetch_submodules: true).
              tap { |f| f.support_file = true }
          ]
        rescue Dependabot::DependencyFileNotFound
          # Ignore lack of a setup.cfg
          []
        end
      end

      def requirements_file?(file)
        return true if file.name.match?(/requirements/x)

        content = file.content.
                  gsub(CONSTRAINT_REGEX, "").
                  gsub(CHILD_REQUIREMENT_REGEX, "")

        tmp_file = DependencyFile.new(name: file.name, content: content)
        Dependabot::Python::FileParser.
          new(dependency_files: [tmp_file], source: source).
          parse.any?
      rescue Dependabot::DependencyFileNotEvaluatable
        false
      end

      def path_setup_file_paths
        requirement_txt_path_setup_file_paths +
          requirement_in_path_setup_file_paths +
          pipfile_path_setup_file_paths
      end

      def requirement_txt_path_setup_file_paths
        (requirements_txt_files + child_requirement_txt_files).
          map { |req_file| parse_path_setup_paths(req_file) }.
          flatten.uniq
      end

      def requirement_in_path_setup_file_paths
        requirements_in_files.
          map { |req_file| parse_path_setup_paths(req_file) }.
          flatten.uniq
      end

      def parse_path_setup_paths(req_file)
        uneditable_reqs =
          req_file.content.
          scan(/^['"]?(?<path>\..*?)(?=\[|#|'|"|$)/).
          flatten.
          map(&:strip).
          reject { |p| p.include?("://") }

        editable_reqs =
          req_file.content.
          scan(/^(?:-e)\s+['"]?(?<path>.*?)(?=\[|#|'|"|$)/).
          flatten.
          map(&:strip).
          reject { |p| p.include?("://") }

        uneditable_reqs + editable_reqs
      end

      def pipfile_path_setup_file_paths
        return [] unless pipfile

        paths = []
        %w(packages dev-packages).each do |dep_type|
          next unless parsed_pipfile[dep_type]

          parsed_pipfile[dep_type].each do |_, req|
            next unless req.is_a?(Hash) && req["path"]

            paths << req["path"]
          end
        end

        paths
      end

      def poetry_path_setup_file_paths
        return [] unless pyproject

        paths = []
        %w(dependencies dev-dependencies).each do |dep_type|
          next unless parsed_pyproject.dig("tool", "poetry", dep_type)

          parsed_pyproject.dig("tool", "poetry", dep_type).each do |_, req|
            next unless req.is_a?(Hash) && req["path"]

            paths << req["path"]
          end
        end

        paths
      end
    end
  end
end
# rubocop:enable Metrics/ClassLength

Dependabot::FileFetchers.register("pip", Dependabot::Python::FileFetcher)
