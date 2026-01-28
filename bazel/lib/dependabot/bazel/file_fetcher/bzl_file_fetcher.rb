# typed: strict
# frozen_string_literal: true

require "dependabot/bazel/file_fetcher"
require "sorbet-runtime"

module Dependabot
  module Bazel
    class FileFetcher < Dependabot::FileFetchers::Base
      # Fetches .bzl files and their dependencies recursively.
      # Handles load() and Label() statements to build a complete dependency graph.
      class BzlFileFetcher
        extend T::Sig

        sig do
          params(
            module_file: DependencyFile,
            fetcher: FileFetcher
          ).void
        end
        def initialize(module_file:, fetcher:)
          @module_file = module_file
          @fetcher = fetcher
          @visited_bzl_files = T.let(Set.new, T::Set[String])
        end

        sig { returns(T::Array[DependencyFile]) }
        def fetch_bzl_files
          content = T.must(@module_file.content)
          bzl_file_paths = extract_bzl_file_paths(content)
          fetch_bzl_files_recursively(bzl_file_paths)
        end

        private

        sig { returns(DependencyFile) }
        attr_reader :module_file

        sig { returns(FileFetcher) }
        attr_reader :fetcher

        sig { returns(T::Set[String]) }
        attr_reader :visited_bzl_files

        # Fetches .bzl files recursively, following their load() and Label() dependencies.
        sig { params(paths: T::Array[String]).returns(T::Array[DependencyFile]) }
        def fetch_bzl_files_recursively(paths)
          files = T.let([], T::Array[DependencyFile])

          paths.each do |path|
            next if visited_bzl_files.include?(path)

            fetched_file = fetcher.send(:fetch_file_if_present, path)
            next unless fetched_file

            files << fetched_file
            visited_bzl_files.add(path)

            if path.end_with?(".bzl")
              bzl_deps = extract_bzl_load_dependencies(fetched_file.content, path)
              files += fetch_bzl_files_recursively(bzl_deps)
            end
          end

          files
        end

        # Extracts .bzl file paths from use_extension() and use_repo_rule() calls.
        # Only extracts workspace-relative paths (//...) and filters out external Bazel
        # repositories (@repo//...) since those files don't exist in the current repository.
        sig { params(content: String).returns(T::Array[String]) }
        def extract_bzl_file_paths(content)
          extract_use_extension_paths(content) + extract_use_repo_rule_paths(content)
        end

        sig { params(content: String).returns(T::Array[String]) }
        def extract_use_extension_paths(content)
          content.scan(%r{use_extension\s*\(\s*"//([^"]+)"}).filter_map do |match|
            path = T.must(match[0]).tr(":", "/").sub(%r{^/}, "")
            path if path.end_with?(".bzl")
          end
        end

        sig { params(content: String).returns(T::Array[String]) }
        def extract_use_repo_rule_paths(content)
          content.scan(%r{use_repo_rule\s*\(\s*"//([^"]+)"}).filter_map do |match|
            path = T.must(match[0]).tr(":", "/").sub(%r{^/}, "")
            path if path.end_with?(".bzl")
          end
        end

        # Extracts file dependencies from load() and Label() statements.
        # Only extracts workspace-relative (//...) and file-relative (:...) paths.
        # External Bazel repositories (@repo//...) are excluded since those files
        # exist in different repositories, not the current one being analyzed.
        sig { params(content: String, file_path: String).returns(T::Array[String]) }
        def extract_bzl_load_dependencies(content, file_path)
          paths = []
          file_dir = File.dirname(file_path)

          content.scan(%r{load\s*\(\s*"(//[^"]+|:[^"]+)"}) do |match|
            path = PathConverter.label_to_path(match[0], context_dir: file_dir)
            paths << path unless path.empty?
          end

          content.scan(%r{Label\s*\(\s*"(//[^"]+|:[^"]+)"\)}) do |match|
            path = PathConverter.label_to_path(match[0], context_dir: file_dir)
            paths << path unless path.empty?
          end

          paths
        end
      end
    end
  end
end
