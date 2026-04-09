# typed: strict
# frozen_string_literal: true

require "toml-rb"
require "sorbet-runtime"

require "dependabot/file_fetchers"
require "dependabot/python/file_fetcher"
require "dependabot/uv"
require "dependabot/uv/requirements_file_matcher"
require "dependabot/uv/file_fetcher/workspace_fetcher"
require "dependabot/errors"

module Dependabot
  module Uv
    class FileFetcher < Dependabot::Python::SharedFileFetcher
      extend T::Sig

      ECOSYSTEM_SPECIFIC_FILES = T.let(%w(uv.lock).freeze, T::Array[String])

      REQUIREMENT_FILE_PATTERNS = T.let(
        {
          extensions: [".txt", ".in"],
          filenames: ["uv.lock"]
        }.freeze,
        T::Hash[Symbol, T::Array[String]]
      )

      # Projects that use README files for metadata may use any of these common names
      README_FILENAMES = T.let(%w(README.md README.rst README.txt README).freeze, T::Array[String])

      # Type alias for path dependency hashes
      PathDependency = T.type_alias { T::Hash[Symbol, String] }

      sig { override.returns(T::Array[String]) }
      def self.ecosystem_specific_required_files
        # uv.lock is not a standalone required file - it requires pyproject.toml
        []
      end

      sig { override.returns(String) }
      def self.required_files_message
        "Repo must contain a requirements.txt, uv.lock, requirements.in, or pyproject.toml"
      end

      private

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def ecosystem_specific_files
        files = []
        files += readme_files
        files += license_files
        files += uv_lock_files
        files += workspace_member_files
        files += version_source_files
        files
      end

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def pyproject_files
        [pyproject].compact
      end

      sig { override.returns(T::Array[T::Hash[Symbol, String]]) }
      def path_dependencies
        [
          *requirement_txt_path_dependencies,
          *requirement_in_path_dependencies,
          *uv_sources_path_dependencies
        ]
      end

      sig { override.returns(T::Array[String]) }
      def additional_path_dependencies
        []
      end

      sig { override.params(file: Dependabot::DependencyFile).returns(T::Boolean) }
      def lockfile_for_compile_file?(file)
        requirements_in_file_matcher.compiled_file?(file)
      end

      sig { override.params(path: String).returns(T::Array[Dependabot::DependencyFile]) }
      def fetch_project_file(path)
        project_files = []

        path = clean_path(File.join(path, "pyproject.toml")) unless sdist_or_wheel?(path)

        return [] if path == "pyproject.toml" && pyproject

        project_files << fetch_file_from_host(
          path,
          fetch_submodules: true
        ).tap { |f| f.support_file = true }

        project_files
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def workspace_member_files
        workspace_fetcher.workspace_member_files
      end

      sig { returns(WorkspaceFetcher) }
      def workspace_fetcher
        @workspace_fetcher ||= T.let(WorkspaceFetcher.new(self, pyproject), T.nilable(WorkspaceFetcher))
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def readme_files
        return [] unless pyproject

        workspace_fetcher.send(:fetch_readme_files_for, directory, T.must(pyproject))
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def license_files
        return [] unless pyproject

        files = []
        files += fetch_license_files_for(directory, T.must(pyproject))
        files += workspace_fetcher.license_files
        files
      end

      sig do
        params(
          base_path: String,
          pyproject_file: Dependabot::DependencyFile
        ).returns(T::Array[Dependabot::DependencyFile])
      end
      def fetch_license_files_for(base_path, pyproject_file)
        license_paths = extract_license_paths(pyproject_file)
        is_root = base_path == directory

        license_paths.filter_map do |license_path|
          resolved_path = resolve_support_file_path(license_path, base_path)
          next unless resolved_path
          next unless path_within_repo?(resolved_path)

          file = if is_root
                   fetch_file_if_present(resolved_path)
                 else
                   fetch_file_from_host(resolved_path, fetch_submodules: true)
                 end

          next unless file

          file.support_file = true
          file
        rescue Dependabot::DependencyFileNotFound
          Dependabot.logger.info("License file not found: #{resolved_path}")
          nil
        end
      end

      sig { params(pyproject_file: Dependabot::DependencyFile).returns(T::Array[String]) }
      def extract_license_paths(pyproject_file)
        parsed = TomlRB.parse(pyproject_file.content)
        paths = []

        # Handle legacy license = {file = "LICENSE"} format
        license_decl = parsed.dig("project", "license")
        paths << license_decl["file"] if license_decl.is_a?(Hash) && license_decl["file"].is_a?(String)

        # Handle license-files = ["LICENSE", "LICENSES/*"] format (without glob expansion)
        license_files_decl = parsed.dig("project", "license-files")
        if license_files_decl.is_a?(Array)
          license_files_decl.each do |pattern|
            # Only include simple file paths, not glob patterns
            paths << pattern if pattern.is_a?(String) && !pattern.include?("*")
          end
        end

        paths
      rescue TomlRB::ParseError, TomlRB::ValueOverwriteError
        []
      end

      sig { params(file_path: String, base_path: String).returns(T.nilable(String)) }
      def resolve_support_file_path(file_path, base_path)
        return nil if file_path.empty?
        return nil if Pathname.new(file_path).absolute?

        if base_path == directory || base_path == "."
          clean_path(file_path)
        else
          clean_path(File.join(base_path, file_path))
        end
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def version_source_files
        return [] unless pyproject

        files = []
        files += fetch_version_source_files_for(directory, T.must(pyproject))
        files += workspace_fetcher.version_source_files

        files
      end

      sig do
        params(
          base_path: String,
          pyproject_file: Dependabot::DependencyFile
        ).returns(T::Array[Dependabot::DependencyFile])
      end
      def fetch_version_source_files_for(base_path, pyproject_file)
        version_paths = extract_version_source_paths(pyproject_file)
        is_root = base_path == directory

        version_paths.filter_map do |version_path|
          resolved_path = resolve_support_file_path(version_path, base_path)
          next unless resolved_path
          next unless path_within_repo?(resolved_path)

          file = if is_root
                   fetch_file_if_present(resolved_path)
                 else
                   fetch_file_from_host(resolved_path, fetch_submodules: true)
                 end

          next unless file

          file.support_file = true
          file
        rescue Dependabot::DependencyFileNotFound
          Dependabot.logger.info("Version source file not found: #{resolved_path}")
          nil
        end
      end

      sig { params(pyproject_file: Dependabot::DependencyFile).returns(T::Array[String]) }
      def extract_version_source_paths(pyproject_file)
        parsed = TomlRB.parse(pyproject_file.content)
        paths = []

        hatch_version_path = parsed.dig("tool", "hatch", "version", "path")
        paths << hatch_version_path if hatch_version_path.is_a?(String)

        paths
      rescue TomlRB::ParseError, TomlRB::ValueOverwriteError
        []
      end

      sig { params(path: String).returns(T::Boolean) }
      def path_within_repo?(path)
        cleaned = clean_path(path)
        !cleaned.start_with?("../", "/")
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def uv_lock_files
        req_txt_and_in_files.select { |f| f.name.end_with?("uv.lock") } +
          child_uv_lock_files
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def child_uv_lock_files
        child_requirement_files.select { |f| f.name.end_with?("uv.lock") }
      end

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def req_txt_and_in_files
        return @req_txt_and_in_files if @req_txt_and_in_files

        @req_txt_and_in_files = T.let([], T.nilable(T::Array[Dependabot::DependencyFile]))
        @req_txt_and_in_files = T.must(@req_txt_and_in_files) + fetch_requirement_files_from_path
        @req_txt_and_in_files += fetch_requirement_files_from_dirs

        @req_txt_and_in_files
      end

      sig { params(requirements_dir: Dependabot::FileFetchers::RepositoryContent).returns(T::Array[Dependabot::DependencyFile]) }
      def req_files_for_dir(requirements_dir)
        dir = directory.gsub(%r{(^/|/$)}, "")
        relative_reqs_dir =
          requirements_dir.path&.gsub(%r{^/?#{Regexp.escape(dir)}/?}, "")

        fetch_requirement_files_from_path(relative_reqs_dir)
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

      sig { returns(T::Array[{ name: String, file: String }]) }
      def uv_sources_workspace_dependencies
        workspace_fetcher.uv_sources_workspace_dependencies
      end

      sig { returns(Dependabot::Uv::RequiremenstFileMatcher) }
      def requirements_in_file_matcher
        @requirements_in_file_matcher ||= T.let(
          RequiremenstFileMatcher.new(requirements_in_files),
          T.nilable(Dependabot::Uv::RequiremenstFileMatcher)
        )
      end

      sig { params(path: T.nilable(T.any(Pathname, String))).returns(T::Array[Dependabot::DependencyFile]) }
      def fetch_requirement_files_from_path(path = nil)
        contents = path ? repo_contents(dir: path) : repo_contents
        filter_requirement_files(contents, base_path: path)
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def fetch_requirement_files_from_dirs
        repo_contents
          .select { |f| T.unsafe(f).type == "dir" }
          .flat_map { |dir| req_files_for_dir(dir) }
      end

      sig do
        params(
          contents: T::Array[Dependabot::FileFetchers::RepositoryContent],
          base_path: T.nilable(T.any(Pathname, String))
        ).returns(T::Array[Dependabot::DependencyFile])
      end
      def filter_requirement_files(contents, base_path: nil)
        contents
          .select { |f| T.unsafe(f).type == "file" }
          .select { |f| file_matches_requirement_pattern?(T.unsafe(f).name) }
          .reject { |f| T.unsafe(f).size > MAX_FILE_SIZE }
          .map { |f| fetch_file_with_path(T.unsafe(f).name, base_path) }
          .select { |f| T.must(REQUIREMENT_FILE_PATTERNS[:filenames]).include?(f.name) || requirements_file?(f) }
      end

      sig { params(filename: String).returns(T::Boolean) }
      def file_matches_requirement_pattern?(filename)
        T.must(REQUIREMENT_FILE_PATTERNS[:extensions]).any? { |ext| filename.end_with?(ext) } ||
          T.must(REQUIREMENT_FILE_PATTERNS[:filenames]).any?(filename)
      end

      sig do
        params(
          filename: T.any(Pathname, String),
          base_path: T.nilable(T.any(Pathname, String))
        ).returns(Dependabot::DependencyFile)
      end
      def fetch_file_with_path(filename, base_path)
        path = base_path ? File.join(base_path, filename) : filename
        fetch_file_from_host(path)
      end
    end
  end
end

Dependabot::FileFetchers.register("uv", Dependabot::Uv::FileFetcher)
