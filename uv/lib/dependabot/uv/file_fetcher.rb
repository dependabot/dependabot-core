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

# Type definitions for repository file structures
module Dependabot
  module Uv
    # Structure representing a file or directory in the repository
    RepoFileStruct = T.type_alias { T.any(OpenStruct, T::Struct) }
    
    # Hash representing a path dependency
    PathDependency = T.type_alias { T::Hash[Symbol, String] }
    
    # Hash representing TOML content
    TomlContent = T.type_alias { T::Hash[String, T.untyped] }
  end
end

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

      sig { override.params(filenames: T::Array[String]).returns(T::Boolean) }
      def self.required_files_in?(filenames)
        return true if filenames.any? do |name|
          T.must(REQUIREMENT_FILE_PATTERNS[:extensions]).any? do |ext|
            name.end_with?(ext)
          end
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

      sig { params(fetched_files: T::Array[Dependabot::DependencyFile]).returns(T::Array[Dependabot::DependencyFile]) }
      def uniq_files(fetched_files)
        uniq_files = fetched_files.reject(&:support_file?).uniq
        uniq_files += fetched_files
                      .reject { |f| uniq_files.map(&:name).include?(f.name) }
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def pyproject_files
        [pyproject].compact
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def requirement_files
        [
          *requirements_txt_files,
          *child_requirement_txt_files,
          *constraints_files
        ]
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def python_version_file
        return @python_version_file if defined?(@python_version_file)

        @python_version_file = T.let(fetch_support_file(".python-version"), T.nilable(Dependabot::DependencyFile))

        return @python_version_file if @python_version_file
        return if [".", "/"].include?(directory)

        # Check the top-level for a .python-version file, too
        reverse_path = Pathname.new(directory[0]).relative_path_from(directory)
        @python_version_file =
          fetch_support_file(File.join(reverse_path, ".python-version"))
          &.tap { |f| f.name = ".python-version" }
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def pyproject
        return @pyproject if defined?(@pyproject)

        @pyproject = T.let(fetch_file_if_present("pyproject.toml"), T.nilable(Dependabot::DependencyFile))
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def requirements_txt_files
        req_txt_and_in_files.select { |f| f.name.end_with?(".txt") }
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def requirements_in_files
        req_txt_and_in_files.select { |f| f.name.end_with?(".in") } +
          child_requirement_in_files
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def uv_lock_files
        req_txt_and_in_files.select { |f| f.name.end_with?("uv.lock") } +
          child_uv_lock_files
      end

      sig { returns(TomlContent) }
      def parsed_pyproject
        raise "No pyproject.toml" unless pyproject

        @parsed_pyproject ||= T.let(TomlRB.parse(T.must(pyproject).content), T.nilable(TomlContent))
      rescue TomlRB::ParseError, TomlRB::ValueOverwriteError
        raise Dependabot::DependencyFileNotParseable, T.must(pyproject).path
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def req_txt_and_in_files
        return @req_txt_and_in_files if @req_txt_and_in_files

        @req_txt_and_in_files = T.let([], T.nilable(T::Array[Dependabot::DependencyFile]))
        @req_txt_and_in_files = T.must(@req_txt_and_in_files) + fetch_requirement_files_from_path
        @req_txt_and_in_files += fetch_requirement_files_from_dirs

        @req_txt_and_in_files
      end

      sig { params(requirements_dir: RepoFileStruct).returns(T::Array[Dependabot::DependencyFile]) }
      def req_files_for_dir(requirements_dir)
        dir = directory.gsub(%r{(^/|/$)}, "")
        relative_reqs_dir =
          requirements_dir.path.gsub(%r{^/?#{Regexp.escape(dir)}/?}, "")

        fetch_requirement_files_from_path(relative_reqs_dir)
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def child_requirement_txt_files
        child_requirement_files.select { |f| f.name.end_with?(".txt") }
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def child_requirement_in_files
        child_requirement_files.select { |f| f.name.end_with?(".in") }
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def child_uv_lock_files
        child_requirement_files.select { |f| f.name.end_with?("uv.lock") }
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def child_requirement_files
        @child_requirement_files ||= T.let(
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
          end, T.nilable(T::Array[Dependabot::DependencyFile])
        )
      end

      sig { params(file: Dependabot::DependencyFile, previously_fetched_files: T::Array[Dependabot::DependencyFile]).returns(T::Array[Dependabot::DependencyFile]) }
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

      sig { returns(T::Array[Dependabot::DependencyFile]) }
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

      sig { returns(T::Array[Dependabot::DependencyFile]) }
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

      sig { params(path: String).returns(T::Array[Dependabot::DependencyFile]) }
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

      sig { params(file: Dependabot::DependencyFile).returns(T::Boolean) }
      def requirements_file?(file)
        return false unless file.content&.valid_encoding?
        return true if file.name.match?(/requirements/x)

        T.must(file.content).lines.all? do |line|
          next true if line.strip.empty?
          next true if line.strip.start_with?("#", "-r ", "-c ", "-e ", "--")

          line.match?(RequirementParser::VALID_REQ_TXT_REQUIREMENT)
        end
      end

      sig { returns(T::Array[PathDependency]) }
      def path_dependencies
        [
          *requirement_txt_path_dependencies,
          *requirement_in_path_dependencies,
          *uv_sources_path_dependencies
        ]
      end

      sig { returns(T::Array[PathDependency]) }
      def requirement_txt_path_dependencies
        (requirements_txt_files + child_requirement_txt_files)
          .map { |req_file| parse_requirement_path_dependencies(req_file) }
          .flatten.uniq { |dep| dep[:path] }
      end

      sig { returns(T::Array[PathDependency]) }
      def requirement_in_path_dependencies
        requirements_in_files
          .map { |req_file| parse_requirement_path_dependencies(req_file) }
          .flatten.uniq { |dep| dep[:path] }
      end

      sig { params(req_file: Dependabot::DependencyFile).returns(T::Array[PathDependency]) }
      def parse_requirement_path_dependencies(req_file)
        # If this is a pip-compile lockfile, rely on whatever path dependencies we found in the main manifest
        return [] if requirements_in_file_matcher.compiled_file?(req_file)

        content = T.must(req_file.content)
        uneditable_reqs = parse_uneditable_requirements(content, req_file.name)
        editable_reqs = parse_editable_requirements(content, req_file.name)

        uneditable_reqs + editable_reqs
      end

      sig { params(content: String, file_name: String).returns(T::Array[PathDependency]) }
      def parse_uneditable_requirements(content, file_name)
        content
          .scan(/(?<name>^['"]?(?:file:)?(?<path>\..*?)(?=\[|#|'|"|$))/)
          .filter_map { |match_data| process_requirement_match(T.cast(match_data, T::Array[String]), file_name, false) }
      end

      sig { params(content: String, file_name: String).returns(T::Array[PathDependency]) }
      def parse_editable_requirements(content, file_name)
        content
          .scan(/(?<name>^(?:-e)\s+['"]?(?:file:)?(?<path>.*?)(?=\[|#|'|"|$))/)
          .filter_map { |match_data| process_requirement_match(T.cast(match_data, T::Array[String]), file_name, true) }
      end

      sig do
        params(
          match_data: T::Array[String],
          file_name: String,
          editable: T::Boolean
        ).returns(T.nilable(PathDependency))
      end
      def process_requirement_match(match_data, file_name, editable)
        name, path = match_data
        return nil if name.nil? || path.nil?
        return nil if path.include?("://")
        return nil if editable && path.include?("git@")

        { name: name.strip, path: path.strip, file: file_name }
      end

      sig { params(path: String).returns(String) }
      def cleanpath(path)
        Pathname.new(path).cleanpath.to_path
      end

      sig { returns(Dependabot::Uv::RequiremenstFileMatcher) }
      def requirements_in_file_matcher
        @requirements_in_file_matcher ||= T.let(RequiremenstFileMatcher.new(requirements_in_files),
                                                T.nilable(Dependabot::Uv::RequiremenstFileMatcher))
      end

      sig { returns(T::Array[PathDependency]) }
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

      sig { params(path: T.nilable(T.any(Pathname, String))).returns(T::Array[Dependabot::DependencyFile]) }
      def fetch_requirement_files_from_path(path = nil)
        contents = path ? repo_contents(dir: path) : repo_contents
        filter_requirement_files(T.cast(contents, T::Array[RepoFileStruct]), base_path: path)
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def fetch_requirement_files_from_dirs
        T.cast(repo_contents, T::Array[RepoFileStruct])
          .select { |f| f.type == "dir" }
          .flat_map { |dir| req_files_for_dir(dir) }
      end

      sig { params(contents: T::Array[RepoFileStruct], base_path: T.nilable(T.any(Pathname, String))).returns(T::Array[Dependabot::DependencyFile]) }
      def filter_requirement_files(contents, base_path: nil)
        contents
          .select { |f| f.type == "file" }
          .select { |f| file_matches_requirement_pattern?(f.name) }
          .reject { |f| f.size > MAX_FILE_SIZE }
          .map { |f| fetch_file_with_path(f.name, base_path) }
          .select { |f| T.must(REQUIREMENT_FILE_PATTERNS[:filenames]).include?(f.name) || requirements_file?(f) }
      end

      sig { params(filename: String).returns(T::Boolean) }
      def file_matches_requirement_pattern?(filename)
        T.must(REQUIREMENT_FILE_PATTERNS[:extensions]).any? { |ext| filename.end_with?(ext) } ||
          T.must(REQUIREMENT_FILE_PATTERNS[:filenames]).any?(filename)
      end

      sig { params(filename: T.any(Pathname, String), base_path: BasicObject).returns(Dependabot::DependencyFile) }
      def fetch_file_with_path(filename, base_path)
        path = base_path ? File.join(base_path, filename) : filename
        fetch_file_from_host(path)
      end
    end
  end
end

Dependabot::FileFetchers.register("uv", Dependabot::Uv::FileFetcher)
