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
        #
        # @param paths [Array<String>] .bzl file paths to fetch
        # @return [Array<DependencyFile>] fetched .bzl files and their dependencies
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
        # Only extracts files from the local repository because Dependabot cannot fetch
        # external repository files (e.g., "@rules_python//...").
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
        # Only extracts local repository files because external repos are not accessible.
        sig { params(content: String, file_path: String).returns(T::Array[String]) }
        def extract_bzl_load_dependencies(content, file_path)
          paths = []
          file_dir = File.dirname(file_path)

          content.scan(%r{load\s*\(\s*"(//[^"]+|:[^"]+)"}) do |match|
            path = resolve_bazel_path(match[0], file_dir)
            paths << path if path
          end

          content.scan(%r{Label\s*\(\s*"(//[^"]+|:[^"]+)"\)}) do |match|
            path = resolve_bazel_path(match[0], file_dir)
            paths << path if path
          end

          paths
        end

        # Resolves Bazel label syntax to filesystem paths.
        # Bazel uses : for target separator and // for absolute paths within the workspace.
        sig { params(bazel_path: String, file_dir: String).returns(T.nilable(String)) }
        def resolve_bazel_path(bazel_path, file_dir)
          path = if bazel_path.start_with?(":")
                   relative_file = bazel_path.sub(/^:/, "")
                   file_dir == "." ? relative_file : "#{file_dir}/#{relative_file}"
                 elsif bazel_path.start_with?("//")
                   bazel_path.tr(":", "/").sub(%r{^/+}, "")
                 else
                   bazel_path
                 end

          path.empty? ? nil : path
        end
      end
    end
  end
end
