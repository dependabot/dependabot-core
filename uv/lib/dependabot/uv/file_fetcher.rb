# typed: strict
# frozen_string_literal: true

require "toml-rb"
require "sorbet-runtime"

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"
require "dependabot/uv/language_version_manager"
require "dependabot/uv/requirements_file_matcher"
require "dependabot/uv/requirement_parser"
require "dependabot/uv/file_parser/pyproject_files_parser"
require "dependabot/uv/file_parser/python_requirement_parser"
require "dependabot/errors"

module Dependabot
  module Uv
    class FileFetcher < Dependabot::FileFetchers::Base
      extend T::Sig
      extend T::Helpers

      CHILD_REQUIREMENT_REGEX = /^-r\s?(?<path>.*\.(?:txt|in))/
      CONSTRAINT_REGEX = /^-c\s?(?<path>.*\.(?:txt|in))/
      DEPENDENCY_TYPES = %w(packages dev-packages).freeze
      REQUIREMENT_FILE_PATTERNS = T.let({
        extensions: [".txt", ".in"],
        filenames: ["uv.lock"]
      }.freeze, T::Hash[Symbol, T::Array[String]])
      MAX_FILE_SIZE = 500_000

      sig do
        override.params(
          source: Dependabot::Source,
          credentials: T::Array[Dependabot::Credential],
          repo_contents_path: T.nilable(String),
          options: T::Hash[String, String]
        ).void
      end
      def initialize(source:, credentials:, repo_contents_path: nil, options: {})
        @source = source
        @credentials = credentials
        @repo_contents_path = repo_contents_path
        @linked_paths = T.let({}, T::Hash[T.untyped, T.untyped])
        @submodules = T.let([], T::Array[T.untyped])
        @options = options
        @files = T.let([], T::Array[DependencyFile])
        @python_version_file = T.let(nil, T.nilable(Dependabot::DependencyFile))
        # @pyproject = T.let(nil, T.nilable(Dependabot::DependencyFile))
        @parsed_pyproject = T.let({}, T::Hash[String, T.untyped])
        @req_txt_and_in_files = T.let([], T::Array[Dependabot::DependencyFile])
        @requirements_in_file_matcher = T.let(nil, T.nilable(Dependabot::Uv::RequirementsFileMatcher))
        @child_requirement_files = T.let([], T::Array[Dependabot::DependencyFile])
      end

      sig { override.params(filenames: T::Array[String]).returns(T::Boolean) }
      def self.required_files_in?(filenames)
        return true if filenames.any? do |name|
          REQUIREMENT_FILE_PATTERNS[:extensions]&.any? { |ext| name.end_with?(ext) }
        end

        # If there is a directory of requirements return true
        return true if filenames.include?("requirements")

        # If this repo is using pyproject.toml return true (uv.lock files require a pyproject.toml)
        filenames.include?("pyproject.toml")
      end

      sig { override.returns(String) }
      def self.required_files_message
        "Repo must contain a requirements.txt, uv.lock, requirements.in, or pyproject.toml" \
      end

      sig { override.returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def ecosystem_versions
        # Hmm... it's weird that this calls file parser methods, but here we are in the file fetcher... for all
        # ecosystems our goal is to extract the user specified versions, so we'll need to do file parsing... so should
        # we move this `ecosystem_versions` metrics method to run in the file parser for all ecosystems? Downside is if
        # file parsing blows up, this metric isn't emitted, but reality is we have to parse anyway... as we want to know
        # the user-specified range of versions, not the version Dependabot chose to run.
        python_requirement_parser = FileParser::PythonRequirementParser.new(dependency_files: files)
        language_version_manager = LanguageVersionManager.new(python_requirement_parser: python_requirement_parser)
        Dependabot.logger.info("Dependabot is using Python version '#{language_version_manager.python_version}'.")
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

        fetched_files += pyproject_files

        fetched_files += requirements_in_files
        fetched_files += requirement_files if requirements_txt_files.any?

        fetched_files += uv_lock_files
        fetched_files += project_files
        fetched_files << python_version_file if python_version_file

        uniq_files(fetched_files)
      end

      private

      sig { params(fetched_files: T::Array[DependencyFile]).returns(T::Array[DependencyFile]) }
      def uniq_files(fetched_files)
        uniq_files = fetched_files.reject(&:support_file?).uniq
        uniq_files += fetched_files
                      .reject { |f| uniq_files.map(&:name).include?(f.name) }
      end

      sig { returns(T::Array[DependencyFile]) }
      def pyproject_files
        [pyproject].compact
      end

      sig { returns(T::Array[DependencyFile]) }
      def requirement_files
        [
          *requirements_txt_files,
          *child_requirement_txt_files,
          *constraints_files
        ]
      end

      sig { returns(T.nilable(DependencyFile)) }
      def python_version_file
        return @python_version_file if defined?(@python_version_file)

        @python_version_file = fetch_support_file(".python-version")

        return @python_version_file if @python_version_file
        return if [".", "/"].include?(directory)

        # Check the top-level for a .python-version file, too
        reverse_path = Pathname.new(directory[0]).relative_path_from(directory)
        @python_version_file =
          fetch_support_file(File.join(reverse_path, ".python-version"))
          &.tap { |f| f.name = ".python-version" }
      end

      sig { returns(T.nilable(DependencyFile)) }
      def pyproject
        @pyproject = T.let(nil, T.nilable(DependencyFile))
        return @pyproject if defined?(@pyproject)

        @pyproject = fetch_file_if_present("pyproject.toml")
      end

      sig { returns(T::Array[DependencyFile]) }
      def requirements_txt_files
        req_txt_and_in_files.select { |f| f.name.end_with?(".txt") }
      end

      sig { returns(T::Array[T.untyped]) }
      def requirements_in_files
        req_txt_and_in_files.select { |f| f.name.end_with?(".in") } +
          child_requirement_in_files
      end

      sig { returns(T::Array[DependencyFile]) }
      def uv_lock_files
        req_txt_and_in_files.select { |f| f.name.end_with?("uv.lock") } +
          child_uv_lock_files
      end

      sig { returns(T::Hash[String, T.untyped]) }
      def parsed_pyproject
        raise "No pyproject.toml" unless pyproject

        @parsed_pyproject = TomlRB.parse(pyproject&.content)
      rescue TomlRB::ParseError, TomlRB::ValueOverwriteError
        raise Dependabot::DependencyFileNotParseable, T.must(pyproject).path
      end

      sig { returns(T::Array[DependencyFile]) }
      def req_txt_and_in_files
        @req_txt_and_in_files = []
        @req_txt_and_in_files += fetch_requirement_files_from_path
        @req_txt_and_in_files += fetch_requirement_files_from_dirs

        @req_txt_and_in_files
      end

      sig { params(requirements_dir: T.untyped).returns(T::Array[DependencyFile]) }
      def req_files_for_dir(requirements_dir)
        dir = directory.gsub(%r{(^/|/$)}, "")
        relative_reqs_dir =
          requirements_dir.path.gsub(%r{^/?#{Regexp.escape(dir)}/?}, "")

        fetch_requirement_files_from_path(relative_reqs_dir)
      end

      sig { returns(T::Array[DependencyFile]) }
      def child_requirement_txt_files
        child_requirement_files.select { |f| f.name.end_with?(".txt") }
      end

      sig { returns(T::Array[DependencyFile]) }
      def child_requirement_in_files
        child_requirement_files.select { |f| f.name.end_with?(".in") }
      end

      sig { returns(T::Array[DependencyFile]) }
      def child_uv_lock_files
        child_requirement_files.select { |f| f.name.end_with?("uv.lock") }
      end

      sig { returns(T::Array[DependencyFile]) }
      def child_requirement_files
        @child_requirement_files =
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

      sig do
        params(file: T.untyped, previously_fetched_files: T::Array[DependencyFile])
          .returns(T::Array[DependencyFile])
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

      sig { returns(T::Array[DependencyFile]) }
      def constraints_files
        all_requirement_files = requirements_txt_files +
                                child_requirement_txt_files

        constraints_paths = all_requirement_files.map do |req_file|
          current_dir = File.dirname(req_file.name)
          paths = T.must(req_file.content).scan(CONSTRAINT_REGEX).flatten

          paths.map do |path|
            path = File.join(current_dir, path) unless current_dir == "."
            cleanpath(path)
          end
        end.flatten.uniq

        constraints_paths.map { |path| fetch_file_from_host(path) }
      end

      sig { returns(T::Array[DependencyFile]) }
      def project_files
        project_files = T.let([], T::Array[Dependabot::DependencyFile])
        unfetchable_deps = []

        path_dependencies.each do |dep|
          path = dep[:path]
          project_files += fetch_project_file(path)
        rescue Dependabot::DependencyFileNotFound
          unfetchable_deps << "\"#{dep[:name]}\" at #{cleanpath(File.join(directory, dep[:file]))}"
        end

        raise Dependabot::PathDependenciesNotReachable, unfetchable_deps if unfetchable_deps.any?

        project_files
      end

      sig { params(path: String).returns(T::Array[DependencyFile]) }
      def fetch_project_file(path)
        project_files = []

        path = cleanpath(File.join(path, "pyproject.toml")) unless sdist_or_wheel?(path)

        return [] if path == "pyproject.toml" && pyproject

        project_files << fetch_file_from_host(
          path,
          fetch_submodules: true
        ).tap { |f| f.support_file = true }

        project_files
      end

      sig { params(path: String).returns(T::Boolean) }
      def sdist_or_wheel?(path)
        path.end_with?(".tar.gz", ".whl", ".zip")
      end

      sig { params(file: DependencyFile).returns(T::Boolean) }
      def requirements_file?(file)
        return false unless file.content&.valid_encoding?
        return true if file.name.match?(/requirements/x)

        T.must(file.content).lines.all? do |line|
          next true if line.strip.empty?
          next true if line.strip.start_with?("#", "-r ", "-c ", "-e ", "--")

          line.match?(RequirementParser::VALID_REQ_TXT_REQUIREMENT)
        end
      end

      sig { returns(T::Array[T.untyped]) }
      def path_dependencies
        [
          *requirement_txt_path_dependencies,
          *requirement_in_path_dependencies,
          *uv_sources_path_dependencies
        ]
      end

      sig { returns(T::Array[T::Hash[Symbol, String]]) }
      def requirement_txt_path_dependencies
        (requirements_txt_files + child_requirement_txt_files)
          .map { |req_file| parse_requirement_path_dependencies(req_file) }
          .flatten.uniq { |dep| dep[:path] }
      end

      sig { returns(T::Array[T::Hash[Symbol, String]]) }
      def requirement_in_path_dependencies
        requirements_in_files
          .map { |req_file| parse_requirement_path_dependencies(req_file) }
          .flatten.uniq { |dep| dep[:path] }
      end

      sig { params(req_file: T.untyped).returns(T::Array[T::Hash[Symbol, String]]) }
      def parse_requirement_path_dependencies(req_file)
        # If this is a pip-compile lockfile, rely on whatever path dependencies we found in the main manifest
        return [] if requirements_in_file_matcher.compiled_file?(req_file)

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

      sig { params(path: String).returns(String) }
      def cleanpath(path)
        Pathname.new(path).cleanpath.to_path
      end

      sig { returns(Dependabot::Uv::RequirementsFileMatcher) }
      def requirements_in_file_matcher
        @requirements_in_file_matcher ||= RequirementsFileMatcher.new(requirements_in_files)
      end

      sig { returns(T::Array[T::Hash[String, String]]) }
      def uv_sources_path_dependencies
        return [] unless pyproject

        uv_sources = parsed_pyproject.dig("tool", "uv", "sources")
        return [] unless uv_sources

        uv_sources.filter_map do |name, source_config|
          if source_config.is_a?(Hash) && source_config["path"]
            {
              name: name,
              path: source_config["path"],
              file: T.must(pyproject).name
            }
          end
        end
      end

      sig { params(path: T.nilable(String)).returns(T::Array[DependencyFile]) }
      def fetch_requirement_files_from_path(path = nil)
        contents = path ? repo_contents(dir: path) : repo_contents
        filter_requirement_files(contents, base_path: path)
      end

      sig { returns(T::Array[DependencyFile]) }
      def fetch_requirement_files_from_dirs
        repo_contents
          .select { |f| f.type == "dir" }
          .flat_map { |dir| req_files_for_dir(dir) }
      end

      sig do
        params(contents: T::Array[T.untyped],
               base_path: T.nilable(String)).returns(T::Array[DependencyFile])
      end
      def filter_requirement_files(contents, base_path: nil)
        contents
          .select { |f| f.type == "file" }
          .select { |f| file_matches_requirement_pattern?(f.name) }
          .reject { |f| f.size > MAX_FILE_SIZE }
          .map { |f| fetch_file_with_path(f.name, base_path) }
          .select { |f| REQUIREMENT_FILE_PATTERNS[:filenames]&.include?(f.name) || requirements_file?(f) }
      end

      sig { params(filename: String).returns(T.nilable(T::Boolean)) }
      def file_matches_requirement_pattern?(filename)
        REQUIREMENT_FILE_PATTERNS[:extensions]&.any? { |ext| filename.end_with?(ext) } ||
          REQUIREMENT_FILE_PATTERNS[:filenames]&.any?(filename)
      end

      sig { params(filename: String, base_path: T.nilable(String)).returns(DependencyFile) }
      def fetch_file_with_path(filename, base_path)
        path = base_path ? File.join(base_path, filename) : filename
        fetch_file_from_host(path)
      end
    end
  end
end

Dependabot::FileFetchers.register("uv", Dependabot::Uv::FileFetcher)
