# typed: strict
# frozen_string_literal: true

require "dependabot/bazel/file_fetcher"
require "sorbet-runtime"

module Dependabot
  module Bazel
    class FileFetcher < Dependabot::FileFetchers::Base
      # Fetches entire directory trees, typically for local_path_override directories.
      # Includes BUILD files to make directories valid Bazel packages.
      class DirectoryTreeFetcher
        extend T::Sig

        SKIP_DIRECTORIES = T.let(%w(.git .bazel-* bazel-* node_modules .github).freeze, T::Array[String])

        sig { params(fetcher: FileFetcher).void }
        def initialize(fetcher:)
          @fetcher = fetcher
        end

        sig { params(directory: String).returns(T::Array[DependencyFile]) }
        def fetch_directory_tree(directory)
          return [] if should_skip_directory?(directory)

          files = T.let([], T::Array[DependencyFile])

          begin
            repo_contents = @fetcher.send(:repo_contents, dir: directory)

            repo_contents.each do |item|
              path = item.path
              next if path.nil? || should_skip_directory?(path)

              case item.type
              when "file"
                fetched_file = @fetcher.send(:fetch_file_if_present, path)
                files << fetched_file if fetched_file
              when "dir"
                files += fetch_directory_tree(path)
              end
            end
          rescue Octokit::NotFound, Dependabot::RepoNotFound, Dependabot::DependencyFileNotFound => e
            Dependabot.logger.warn("Skipping inaccessible directory '#{directory}': #{e.message}")
          end

          files
        end

        sig { params(directories: T::Set[String]).returns(T::Array[DependencyFile]) }
        def fetch_build_files_for_directories(directories)
          files = T.let([], T::Array[DependencyFile])
          directories.each do |dir|
            build_file = @fetcher.send(:fetch_file_if_present, "#{dir}/BUILD") ||
                         @fetcher.send(:fetch_file_if_present, "#{dir}/BUILD.bazel")
            files << build_file if build_file
          end
          files
        end

        private

        sig { returns(FileFetcher) }
        attr_reader :fetcher

        sig { params(dirname: String).returns(T::Boolean) }
        def should_skip_directory?(dirname)
          SKIP_DIRECTORIES.any? do |skip_pattern|
            if skip_pattern.end_with?("*")
              dirname.start_with?(skip_pattern.chomp("*"))
            else
              dirname == skip_pattern || dirname.end_with?("/#{skip_pattern}")
            end
          end
        end
      end
    end
  end
end
