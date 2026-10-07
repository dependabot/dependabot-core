# typed: strict
# frozen_string_literal: true

require "dependabot/bazel/file_fetcher"
require "dependabot/bazel/file_fetcher/path_converter"
require "sorbet-runtime"

module Dependabot
  module Bazel
    class FileFetcher < Dependabot::FileFetchers::Base
      # Extracts include() statements from MODULE.bazel files and fetches the included files.
      # Bazel's include() directive allows splitting MODULE.bazel content across multiple files.
      # The include() statement uses Bazel label syntax: include("//path:file.MODULE.bazel")
      # See https://bazel.build/rules/lib/globals/module#include
      class IncludeExtractor
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
          @visited_files = T.let(Set.new, T::Set[String])
        end

        # Fetches all files included via include() statements, recursively.
        sig { returns([T::Array[DependencyFile], T::Set[String]]) }
        def fetch_included_files
          files = T.let([], T::Array[DependencyFile])
          directories = T.let(Set.new, T::Set[String])

          content = T.must(@module_file.content)
          include_paths = extract_include_paths(content)

          include_paths.each do |path|
            next if @visited_files.include?(path)

            @visited_files.add(path)

            fetched_file = @fetcher.send(:fetch_file_if_present, path)
            next unless fetched_file

            files << fetched_file

            dir = File.dirname(path)
            directories.add(dir) unless dir == "."

            nested_files, nested_dirs = fetch_nested_includes(fetched_file)
            files.concat(nested_files)
            nested_dirs.each { |d| directories.add(d) }
          end

          [files, directories]
        end

        private

        sig { returns(DependencyFile) }
        attr_reader :module_file

        sig { returns(FileFetcher) }
        attr_reader :fetcher

        sig { returns(T::Set[String]) }
        attr_reader :visited_files

        # Extracts file paths from include() statements.
        # Only extracts workspace-relative paths (//...) and filters out external repositories.
        sig { params(content: String).returns(T::Array[String]) }
        def extract_include_paths(content)
          paths = []

          # Match include("//path:file") and include("//path/to:file.MODULE.bazel")
          content.scan(%r{include\s*\(\s*"(//[^"]+)"}) do |match|
            label = match[0]
            path = PathConverter.label_to_path(label)
            paths << path unless path.empty?
          end

          # Match include(":file") for same-directory includes
          content.scan(/include\s*\(\s*"(:[^"]+)"/) do |match|
            label = match[0]
            context_dir = File.dirname(@module_file.name)
            context_dir = nil if context_dir == "."
            path = PathConverter.label_to_path(label, context_dir: context_dir)
            paths << path unless path.empty?
          end

          paths.uniq
        end

        sig { params(included_file: DependencyFile).returns([T::Array[DependencyFile], T::Set[String]]) }
        def fetch_nested_includes(included_file)
          nested_extractor = IncludeExtractor.new(module_file: included_file, fetcher: @fetcher)
          nested_extractor.instance_variable_set(:@visited_files, @visited_files)
          nested_extractor.fetch_included_files
        end
      end
    end
  end
end
