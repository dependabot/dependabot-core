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
        files += uv_lock_files
        files += workspace_member_files
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

      sig { params(requirements_dir: OpenStruct).returns(T::Array[Dependabot::DependencyFile]) }
      def req_files_for_dir(requirements_dir)
        dir = directory.gsub(%r{(^/|/$)}, "")
        relative_reqs_dir =
          T.unsafe(requirements_dir).path.gsub(%r{^/?#{Regexp.escape(dir)}/?}, "")

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
          contents: T::Array[OpenStruct],
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
