# typed: strict
# frozen_string_literal: true

require "dependabot/bazel/file_fetcher"
require "sorbet-runtime"

module Dependabot
  module Bazel
    class FileFetcher < Dependabot::FileFetchers::Base
      # Fetches files referenced by import/try-import statements in .bazelrc.
      # Bazel's .bazelrc supports importing other rc files via:
      #   import path/to/file
      #   import %workspace%/path/to/file
      #   try-import path/to/file
      #   try-import %workspace%/path/to/file
      # See: https://bazel.build/run/bazelrc#imports
      class BazelrcImportFetcher
        extend T::Sig

        sig { params(fetcher: FileFetcher).void }
        def initialize(fetcher:)
          @fetcher = fetcher
          @visited = T.let(Set.new, T::Set[String])
        end

        sig { returns(T::Array[DependencyFile]) }
        def fetch_bazelrc_imports
          bazelrc_file = @fetcher.send(:fetch_file_if_present, ".bazelrc")
          return [] unless bazelrc_file

          fetch_imports_from(bazelrc_file)
        end

        private

        sig { returns(FileFetcher) }
        attr_reader :fetcher

        sig { params(bazelrc_file: DependencyFile).returns(T::Array[DependencyFile]) }
        def fetch_imports_from(bazelrc_file)
          content = T.must(bazelrc_file.content)
          import_paths = extract_import_paths(content)
          files = T.let([], T::Array[DependencyFile])

          import_paths.each do |path|
            next if @visited.include?(path)

            @visited.add(path)

            fetched_file = @fetcher.send(:fetch_file_if_present, path)
            unless fetched_file
              Dependabot.logger.warn(
                "Imported bazelrc file '#{path}' referenced in .bazelrc but not found in repository"
              )
              next
            end

            files << fetched_file
            files += fetch_imports_from(fetched_file)
          rescue Dependabot::DependencyFileNotFound
            Dependabot.logger.warn(
              "Imported bazelrc file '#{path}' referenced in .bazelrc but not found in repository"
            )
          end

          files
        end

        sig { params(content: String).returns(T::Array[String]) }
        def extract_import_paths(content)
          paths = T.let([], T::Array[String])

          content.each_line do |line|
            line = line.strip
            next if line.empty? || line.start_with?("#")

            match = line.match(/\A(?:try-)?import\s+(.+)\z/)
            next unless match

            path = T.must(match[1]).strip
            path = path.delete_prefix("%workspace%/")

            next if path.empty?
            next if path.start_with?("/")

            paths << path
          end

          paths.uniq
        end
      end
    end
  end
end
