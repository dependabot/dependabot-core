# typed: strict
# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

module Dependabot
  module Bazel
    class FileFetcher < Dependabot::FileFetchers::Base
      extend T::Sig

      require_relative "file_fetcher/path_converter"
      require_relative "file_fetcher/bzl_file_fetcher"
      require_relative "file_fetcher/module_path_extractor"
      require_relative "file_fetcher/directory_tree_fetcher"
      require_relative "file_fetcher/downloader_config_fetcher"

      WORKSPACE_FILES = T.let(%w(WORKSPACE WORKSPACE.bazel).freeze, T::Array[String])
      MODULE_FILE = T.let("MODULE.bazel", String)
      CONFIG_FILES = T.let(
        %w(.bazelrc MODULE.bazel.lock .bazelversion maven_install.json BUILD BUILD.bazel).freeze, T::Array[String]
      )

      sig { override.returns(String) }
      def self.required_files_message
        "Repo must contain a WORKSPACE, WORKSPACE.bazel, or MODULE.bazel file."
      end

      sig { override.params(filenames: T::Array[String]).returns(T::Boolean) }
      def self.required_files_in?(filenames)
        filenames.any? { |name| WORKSPACE_FILES.include?(name) || name.end_with?(MODULE_FILE) }
      end

      sig { override.returns(T::Array[DependencyFile]) }
      def fetch_files
        fetched_files = T.let([], T::Array[DependencyFile])
        fetched_files += workspace_files
        fetched_files += module_files
        fetched_files += config_files
        fetched_files += referenced_files_from_modules
        fetched_files += downloader_config_files

        return fetched_files if fetched_files.any?

        raise Dependabot::DependencyFileNotFound.new(nil, self.class.required_files_message)
      end

      sig { override.returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def ecosystem_versions
        bazel_version = "unknown"

        bazelversion_file = fetch_file_if_present(".bazelversion")
        bazel_version = T.must(bazelversion_file.content).strip if bazelversion_file

        { package_managers: { "bazel" => bazel_version } }
      end

      private

      sig { returns(T::Array[DependencyFile]) }
      def workspace_files
        files = T.let([], T::Array[DependencyFile])

        WORKSPACE_FILES.each do |filename|
          file = fetch_file_if_present(filename)
          files << file if file
        end

        files
      end

      sig { returns(T::Array[DependencyFile]) }
      def module_files
        files = T.let([], T::Array[DependencyFile])

        module_file_items.each do |item|
          file = fetch_file_if_present(item.name)
          files << file if file
        end

        files
      end

      sig { returns(T::Array[T.untyped]) }
      def module_file_items
        repo_contents(raise_errors: false).select { |f| f.type == "file" && f.name.end_with?(MODULE_FILE) }
      end

      sig { returns(T::Array[DependencyFile]) }
      def config_files
        files = T.let([], T::Array[DependencyFile])

        CONFIG_FILES.map do |filename|
          file = if filename == ".bazelversion"
                   fetch_bazelversion_file
                 else
                   fetch_file_if_present(filename)
                 end
          files << file if file
        end

        files
      end

      sig { returns(T.nilable(DependencyFile)) }
      def fetch_bazelversion_file
        file = fetch_file_if_present(".bazelversion")
        return file if file
        return if [".", "/"].include?(directory)

        fetch_file_from_parent_directories(".bazelversion")
      end

      sig { params(filename: String).returns(T.nilable(DependencyFile)) }
      def fetch_file_from_parent_directories(filename)
        (1..directory.split("/").count).each do |i|
          candidate_path = ("../" * i) + filename
          file = fetch_file_if_present(candidate_path)
          if file
            file.name = filename
            return file
          end
        end
        nil
      end

      # Fetches files referenced in MODULE.bazel and their associated BUILD files.
      # Bazel requires BUILD files to recognize directories as valid packages.
      sig { returns(T::Array[DependencyFile]) }
      def referenced_files_from_modules
        files = T.let([], T::Array[DependencyFile])
        directories_with_files = T.let(Set.new, T::Set[String])
        local_override_directories = T.let(Set.new, T::Set[String])
        tree_fetcher = DirectoryTreeFetcher.new(fetcher: self)

        module_files.each do |module_file|
          extractor = ModulePathExtractor.new(module_file: module_file)
          file_paths, directory_paths = extractor.extract_paths

          bzl_fetcher = BzlFileFetcher.new(module_file: module_file, fetcher: self)
          bzl_files = bzl_fetcher.fetch_bzl_files

          bzl_files.each do |file|
            dir = File.dirname(file.name)
            directories_with_files.add(dir) unless dir == "."
          end

          files += bzl_files
          files += fetch_paths_and_track_directories(file_paths, directories_with_files)

          directory_paths.each { |dir| local_override_directories.add(dir) unless dir == "." }
        end

        files += tree_fetcher.fetch_build_files_for_directories(directories_with_files)
        files += fetch_local_override_directory_trees(local_override_directories)

        files
      end

      # Fetches files and tracks their directories for BUILD file resolution.
      sig do
        params(
          paths: T::Array[String],
          directories: T::Set[String]
        ).returns(T::Array[DependencyFile])
      end
      def fetch_paths_and_track_directories(paths, directories)
        files = T.let([], T::Array[DependencyFile])
        paths.each do |path|
          fetched_file = fetch_file_if_present(path)
          next unless fetched_file

          files << fetched_file
          dir = File.dirname(path)
          directories.add(dir) unless dir == "."
        end
        files
      end

      # Fetches complete directory trees for local module overrides.
      sig { params(directories: T::Set[String]).returns(T::Array[DependencyFile]) }
      def fetch_local_override_directory_trees(directories)
        tree_fetcher = DirectoryTreeFetcher.new(fetcher: self)
        files = T.let([], T::Array[DependencyFile])
        directories.each { |dir| files += tree_fetcher.fetch_directory_tree(dir) }
        files
      end

      sig { returns(T::Array[DependencyFile]) }
      def downloader_config_files
        config_fetcher = DownloaderConfigFetcher.new(fetcher: self)
        config_fetcher.fetch_downloader_config_files
      end
    end
  end
end

Dependabot::FileFetchers.register("bazel", Dependabot::Bazel::FileFetcher)
