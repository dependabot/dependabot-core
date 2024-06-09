# typed: true
# frozen_string_literal: true

require "toml-rb"
require "sorbet-runtime"

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"
require "dependabot/python/language_version_manager"
require "dependabot/python/pip_compile_file_matcher"
require "dependabot/python/requirement_parser"
require "dependabot/python/file_parser/pyproject_files_parser"
require "dependabot/python/file_parser/python_requirement_parser"
require "dependabot/errors"

module Dependabot
  module Python
    class FileFetcher < Dependabot::FileFetchers::Base
      extend T::Sig
      extend T::Helpers

      CHILD_REQUIREMENT_REGEX = /^-r\s?(?<path>.*\.(?:txt|in))/
      CONSTRAINT_REGEX = /^-c\s?(?<path>.*\.(?:txt|in))/
      DEPENDENCY_TYPES = %w(packages dev-packages).freeze

      def self.required_files_in?(filenames)
        return true if filenames.any? { |name| name.end_with?(".txt", ".in") }

        # If there is a directory of requirements return true
        return true if filenames.include?("requirements")

        # If this repo is using a Pipfile return true
        return true if filenames.include?("Pipfile")

        # If this repo is using pyproject.toml return true
        return true if filenames.include?("pyproject.toml")

        return true if filenames.include?("setup.py")

        filenames.include?("setup.cfg")
      end

      def self.required_files_message
        "Repo must contain a requirements.txt, setup.py, setup.cfg, pyproject.toml, " \
          "or a Pipfile."
      end

      def ecosystem_versions
        # Hmm... it's weird that this calls file parser methods, but here we are in the file fetcher... for all
        # ecosystems our goal is to extract the user specified versions, so we'll need to do file parsing... so should
        # we move this `ecosystem_versions` metrics method to run in the file parser for all ecosystems? Downside is if
        # file parsing blows up, this metric isn't emitted, but reality is we have to parse anyway... as we want to know
        # the user-specified range of versions, not the version Dependabot chose to run.
        python_requirement_parser = FileParser::PythonRequirementParser.new(dependency_files: files)
        language_version_manager = LanguageVersionManager.new(python_requirement_parser: python_requirement_parser)
        Dependabot.logger.info("Dependabot is using Python version '#{language_version_manager.python_major_minor}'.")
        {
          languages: {
            python: {
              # TODO: alternatively this could use `python_requirement_parser.user_specified_requirements` which
              # returns an array... which we could flip to return a hash of manifest name => version
              # string and then check for min/max versions... today it simply defaults to
              # array.first which seems rather arbitrary.
              "raw" => language_version_manager.user_specified_python_version || "unknown",
              "max" => language_version_manager.python_major_minor || "unknown"
            }
          }
        }
      end

      sig { override.returns(T::Array[DependencyFile]) }
      def fetch_files
        fetched_files = []

        fetched_files += pipenv_files
        fetched_files += pyproject_files

        fetched_files += requirements_in_files
        fetched_files += requirement_files if requirements_txt_files.any?

        fetched_files << setup_file if setup_file
        fetched_files << setup_cfg_file if setup_cfg_file
        fetched_files += project_files
        fetched_files << pip_conf if pip_conf
        fetched_files << python_version_file if python_version_file

        uniq_files(fetched_files)
      end

      private

      def uniq_files(fetched_files)
        uniq_files = fetched_files.reject(&:support_file?).uniq
        uniq_files += fetched_files
                      .reject { |f| uniq_files.map(&:name).include?(f.name) }
      end

      def pipenv_files
        [pipfile, pipfile_lock].compact
      end

      def pyproject_files
        [pyproject, poetry_lock, pdm_lock].compact
      end

      def requirement_files
        [
          *requirements_txt_files,
          *child_requirement_txt_files,
          *constraints_files
        ]
      end

      def setup_file
        return @setup_file if defined?(@setup_file)

        @setup_file = fetch_file_if_present("setup.py")
      end

      def setup_cfg_file
        return @setup_cfg_file if defined?(@setup_cfg_file)

        @setup_cfg_file = fetch_file_if_present("setup.cfg")
      end

      def pip_conf
        return @pip_conf if defined?(@pip_conf)

        @pip_conf = fetch_support_file("pip.conf")
      end

      def python_version_file
        @python_version_file ||= T.let(
          begin
            file = fetch_support_file(".python-version")
            return file if file

            return if [".", "/"].include?(directory)

            reverse_path = Pathname.new(directory[0]).relative_path_from(directory)
            fetch_support_file(File.join(reverse_path, ".python-version"))
              &.tap { |f| f.name = ".python-version" }
          end,
          T.nilable(DependencyFile)
        )
      end

      def pipfile
        return @pipfile if defined?(@pipfile)

        @pipfile = fetch_file_if_present("Pipfile")
      end

      def pipfile_lock
        return @pipfile_lock if defined?(@pipfile_lock)

        @pipfile_lock = fetch_file_if_present("Pipfile.lock")
      end

      def pyproject
        return @pyproject if defined?(@pyproject)

        @pyproject = fetch_file_if_present("pyproject.toml")
      end

      def poetry_lock
        return @poetry_lock if defined?(@poetry_lock)

        @poetry_lock = fetch_file_if_present("poetry.lock")
      end

      def pdm_lock
        return @pdm_lock if defined?(@pdm_lock)

        @pdm_lock = fetch_file_if_present("pdm.lock")
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

        repo_contents
          .select { |f| f.type == "file" }
          .select { |f| f.name.end_with?(".txt", ".in") }
          .reject { |f| f.size > 500_000 }
          .map { |f| fetch_file_from_host(f.name) }
          .select { |f| requirements_file?(f) }
          .each { |f| @req_txt_and_in_files << f }

        repo_contents
          .select { |f| f.type == "dir" }
          .each { |f| @req_txt_and_in_files += req_files_for_dir(f) }

        @req_txt_and_in_files
      end

      def req_files_for_dir(requirements_dir)
        dir = directory.gsub(%r{(^/|/$)}, "")
        relative_reqs_dir =
          requirements_dir.path.gsub(%r{^/?#{Regexp.escape(dir)}/?}, "")

        repo_contents(dir: relative_reqs_dir)
          .select { |f| f.type == "file" }
          .select { |f| f.name.end_with?(".txt", ".in") }
          .reject { |f| f.size > 500_000 }
          .map { |f| fetch_file_from_host("#{relative_reqs_dir}/#{f.name}") }
          .select { |f| requirements_file?(f) }
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
          path = cleanpath(path)

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
          current_dir = File.dirname(req_file.name)
          paths = req_file.content.scan(CONSTRAINT_REGEX).flatten

          paths.map do |path|
            path = File.join(current_dir, path) unless current_dir == "."
            cleanpath(path)
          end
        end.flatten.uniq

        constraints_paths.map { |path| fetch_file_from_host(path) }
      end

      def project_files
        project_files = T.let([], T::Array[Dependabot::DependencyFile])
        unfetchable_deps = []

        path_dependencies.each do |dep|
          path = dep[:path]
          project_files += fetch_project_file(path)
        rescue Dependabot::DependencyFileNotFound => e
          unfetchable_deps << if sdist_or_wheel?(path)
                                e.file_path&.gsub(%r{^/}, "")
                              else
                                "\"#{dep[:name]}\" at #{cleanpath(File.join(directory, dep[:file]))}"
                              end
        end

        poetry_path_dependencies.each do |path|
          project_files += fetch_project_file(path)
        rescue Dependabot::DependencyFileNotFound => e
          unfetchable_deps << e.file_path&.gsub(%r{^/}, "")
        end

        raise Dependabot::PathDependenciesNotReachable, unfetchable_deps if unfetchable_deps.any?

        project_files
      end

      def fetch_project_file(path)
        project_files = []

        path = cleanpath(File.join(path, "setup.py")) unless sdist_or_wheel?(path)

        return [] if path == "setup.py" && setup_file

        project_files <<
          begin
            fetch_file_from_host(
              path,
              fetch_submodules: true
            ).tap { |f| f.support_file = true }
          rescue Dependabot::DependencyFileNotFound
            # For projects with pyproject.toml attempt to fetch a pyproject.toml
            # at the given path instead of a setup.py.
            fetch_file_from_host(
              path.gsub("setup.py", "pyproject.toml"),
              fetch_submodules: true
            ).tap { |f| f.support_file = true }
          end

        return project_files unless path.end_with?(".py")

        project_files + cfg_files_for_setup_py(path)
      end

      def sdist_or_wheel?(path)
        path.end_with?(".tar.gz", ".whl", ".zip")
      end

      def cfg_files_for_setup_py(path)
        cfg_path = path.gsub(/\.py$/, ".cfg")

        begin
          [
            fetch_file_from_host(cfg_path, fetch_submodules: true)
              .tap { |f| f.support_file = true }
          ]
        rescue Dependabot::DependencyFileNotFound
          # Ignore lack of a setup.cfg
          []
        end
      end

      def requirements_file?(file)
        return false unless file.content.valid_encoding?
        return true if file.name.match?(/requirements/x)

        file.content.lines.all? do |line|
          next true if line.strip.empty?
          next true if line.strip.start_with?("#", "-r ", "-c ", "-e ", "--")

          line.match?(RequirementParser::VALID_REQ_TXT_REQUIREMENT)
        end
      end

      def path_dependencies
        requirement_txt_path_dependencies +
          requirement_in_path_dependencies +
          pipfile_path_dependencies
      end

      def requirement_txt_path_dependencies
        (requirements_txt_files + child_requirement_txt_files)
          .map { |req_file| parse_requirement_path_dependencies(req_file) }
          .flatten.uniq { |dep| dep[:path] }
      end

      def requirement_in_path_dependencies
        requirements_in_files
          .map { |req_file| parse_requirement_path_dependencies(req_file) }
          .flatten.uniq { |dep| dep[:path] }
      end

      def parse_requirement_path_dependencies(req_file)
        # If this is a pip-compile lockfile, rely on whatever path dependencies we found in the main manifest
        return [] if pip_compile_file_matcher.lockfile_for_pip_compile_file?(req_file)

        uneditable_reqs =
          req_file.content
                  .scan(/(?<name>^['"]?(?:file:)?(?<path>\..*?)(?=\[|#|'|"|$))/)
                  .filter_map do |n, p|
                    { name: n.strip, path: p.strip, file: req_file.name } unless p.include?("://")
                  end

        editable_reqs =
          req_file.content
                  .scan(/(?<name>^(?:-e)\s+['"]?(?:file:)?(?<path>.*?)(?=\[|#|'|"|$))/)
                  .filter_map do |n, p|
                    { name: n.strip, path: p.strip, file: req_file.name } unless p.include?("://") || p.include?("git@")
                  end

        uneditable_reqs + editable_reqs
      end

      def pipfile_path_dependencies
        return [] unless pipfile

        deps = []
        DEPENDENCY_TYPES.each do |dep_type|
          next unless parsed_pipfile[dep_type]

          parsed_pipfile[dep_type].each do |_, req|
            next unless req.is_a?(Hash) && req["path"]

            deps << { name: req["path"], path: req["path"], file: pipfile.name }
          end
        end

        deps
      end

      def poetry_path_dependencies
        return [] unless pyproject

        paths = []
        Dependabot::Python::FileParser::PyprojectFilesParser::POETRY_DEPENDENCY_TYPES.each do |dep_type|
          next unless parsed_pyproject.dig("tool", "poetry", dep_type)

          parsed_pyproject.dig("tool", "poetry", dep_type).each do |_, req|
            next unless req.is_a?(Hash) && req["path"]

            paths << req["path"]
          end
        end

        paths
      end

      def cleanpath(path)
        Pathname.new(path).cleanpath.to_path
      end

      def pip_compile_file_matcher
        @pip_compile_file_matcher ||= PipCompileFileMatcher.new(requirements_in_files)
      end
    end
  end
end

Dependabot::FileFetchers.register("pip", Dependabot::Python::FileFetcher)
