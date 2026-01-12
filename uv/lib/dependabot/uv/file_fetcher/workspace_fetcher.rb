# typed: strict
# frozen_string_literal: true

require "toml-rb"
require "sorbet-runtime"
require "dependabot/dependency_file"
require "dependabot/uv/file_fetcher"

module Dependabot
  module Uv
    class FileFetcher < Dependabot::Python::SharedFileFetcher
      class WorkspaceFetcher
        extend T::Sig

        README_FILENAMES = T.let(%w(README.md README.rst README.txt README).freeze, T::Array[String])

        sig do
          params(
            file_fetcher: Dependabot::Uv::FileFetcher,
            pyproject: T.nilable(Dependabot::DependencyFile)
          ).void
        end
        def initialize(file_fetcher, pyproject)
          @file_fetcher = file_fetcher
          @pyproject = pyproject
          @parsed_pyproject = T.let(nil, T.nilable(T::Hash[String, T.untyped]))
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def workspace_member_files
          return [] unless @pyproject

          workspace_member_paths.flat_map do |member_path|
            member_pyproject = fetch_workspace_member_pyproject(member_path)
            member_readmes = fetch_readme_files_for(member_path, member_pyproject)

            [member_pyproject] + member_readmes
          rescue Dependabot::DependencyFileNotFound
            []
          end
        end

        sig { returns(T::Array[{ name: String, file: String }]) }
        def uv_sources_workspace_dependencies
          return [] unless @pyproject

          uv_sources = parsed_pyproject.dig("tool", "uv", "sources")
          return [] unless uv_sources

          uv_sources.filter_map do |name, source_config|
            if source_config.is_a?(Hash) && source_config["workspace"] == true
              {
                name: T.cast(name, String),
                file: @pyproject.name
              }
            end
          end
        end

        private

        sig { params(member_path: String).returns(Dependabot::DependencyFile) }
        def fetch_workspace_member_pyproject(member_path)
          pyproject_path = clean_path(File.join(member_path, "pyproject.toml"))
          pyproject_file = fetch_file_from_host(pyproject_path, fetch_submodules: true)
          pyproject_file.support_file = true
          pyproject_file
        end

        sig do
          params(
            path: String,
            pyproject_file: Dependabot::DependencyFile
          ).returns(T::Array[Dependabot::DependencyFile])
        end
        def fetch_readme_files_for(path, pyproject_file)
          readme_candidates = readme_candidates_from_pyproject(pyproject_file)
          is_root_project = path == directory

          readme_candidates.filter_map do |filename|
            file = fetch_readme_file(filename, path, is_root_project)
            next unless file

            file.support_file = true
            file
          rescue Dependabot::DependencyFileNotFound
            nil
          end
        rescue TomlRB::ParseError, TomlRB::ValueOverwriteError
          []
        end

        sig { params(pyproject_file: Dependabot::DependencyFile).returns(T::Array[String]) }
        def readme_candidates_from_pyproject(pyproject_file)
          parsed_content = TomlRB.parse(pyproject_file.content)
          readme_declaration = parsed_content.dig("project", "readme")

          case readme_declaration
          when String then [readme_declaration]
          when Hash
            readme_declaration["file"].is_a?(String) ? [T.cast(readme_declaration["file"], String)] : README_FILENAMES
          else
            README_FILENAMES
          end
        end

        sig do
          params(
            filename: String,
            path: String,
            is_root_project: T::Boolean
          ).returns(T.nilable(Dependabot::DependencyFile))
        end
        def fetch_readme_file(filename, path, is_root_project)
          if is_root_project
            fetch_file_if_present(filename)
          else
            file_path = clean_path(File.join(path, filename))
            fetch_file_from_host(file_path, fetch_submodules: true)
          end
        end

        sig { returns(T::Array[String]) }
        def workspace_member_paths
          return [] unless @pyproject

          members = parsed_pyproject.dig("tool", "uv", "workspace", "members")
          return [] unless members.is_a?(Array)

          members.grep(String).flat_map { |pattern| expand_workspace_pattern(pattern) }
        end

        sig { params(pattern: String).returns(T::Array[String]) }
        def expand_workspace_pattern(pattern)
          return [pattern] unless pattern.include?("*")

          base_directory = extract_base_directory_from_glob(pattern)
          directory_paths = fetch_directory_paths_for_matching(base_directory)
          match_paths_against_pattern(directory_paths, pattern)
        end

        sig { params(glob_pattern: String).returns(String) }
        def extract_base_directory_from_glob(glob_pattern)
          pattern_without_dot_slash = glob_pattern.gsub(%r{^\./}, "")
          path_before_glob = pattern_without_dot_slash.split("*").first&.gsub(%r{(?<=/)[^/]*$}, "") || "."
          path_before_glob.empty? ? "." : path_before_glob.chomp("/")
        end

        sig { params(base_dir: String).returns(T::Array[String]) }
        def fetch_directory_paths_for_matching(base_dir)
          normalized_directory = directory.gsub(%r{(^/|/$)}, "")

          repo_contents(dir: base_dir, raise_errors: false)
            .select { |file| T.unsafe(file).type == "dir" }
            .map { |f| T.unsafe(f).path.gsub(%r{^/?#{Regexp.escape(normalized_directory)}/?}, "") }
        end

        sig { params(paths: T::Array[String], pattern: String).returns(T::Array[String]) }
        def match_paths_against_pattern(paths, pattern)
          pattern_without_dot_slash = pattern.gsub(%r{^\./}, "")
          paths.select { |path| File.fnmatch?(pattern_without_dot_slash, path, File::FNM_PATHNAME) }
        end

        sig { returns(T::Hash[String, T.untyped]) }
        def parsed_pyproject
          cached = @parsed_pyproject
          return cached if cached
          return {} unless @pyproject

          @parsed_pyproject = TomlRB.parse(@pyproject.content)
        end

        # Delegate methods to file_fetcher
        sig { params(path: T.nilable(T.any(Pathname, String))).returns(String) }
        def clean_path(path)
          @file_fetcher.send(:clean_path, path)
        end

        sig do
          params(
            filename: String,
            fetch_submodules: T::Boolean
          ).returns(Dependabot::DependencyFile)
        end
        def fetch_file_from_host(filename, fetch_submodules: false)
          @file_fetcher.send(:fetch_file_from_host, filename, fetch_submodules: fetch_submodules)
        end

        sig { params(filename: String).returns(T.nilable(Dependabot::DependencyFile)) }
        def fetch_file_if_present(filename)
          @file_fetcher.send(:fetch_file_if_present, filename)
        end

        sig do
          params(
            dir: T.nilable(String),
            raise_errors: T::Boolean
          ).returns(T::Array[OpenStruct])
        end
        def repo_contents(dir: nil, raise_errors: true)
          @file_fetcher.send(:repo_contents, dir: dir, raise_errors: raise_errors)
        end

        sig { returns(String) }
        def directory
          @file_fetcher.send(:directory)
        end
      end
    end
  end
end
