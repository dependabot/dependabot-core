# typed: strict
# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

module Dependabot
  module Bazel
    class FileFetcher < Dependabot::FileFetchers::Base
      extend T::Sig

      WORKSPACE_FILES = T.let(%w(WORKSPACE WORKSPACE.bazel).freeze, T::Array[String])
      MODULE_FILE = T.let("MODULE.bazel", String)
      CONFIG_FILES = T.let(
        %w(.bazelrc MODULE.bazel.lock .bazelversion maven_install.json BUILD BUILD.bazel).freeze, T::Array[String]
      )
      SKIP_DIRECTORIES = T.let(%w(.git .bazel-* bazel-* node_modules .github).freeze, T::Array[String])

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
        unless allow_beta_ecosystems?
          raise Dependabot::DependencyFileNotFound.new(
            nil,
            "Bazel support is currently in beta. To enable it, add `enable_beta_ecosystems: true` to the" \
            " top-level of your `dependabot.yml`. See " \
            "https://docs.github.com/en/code-security/dependabot/working-with-dependabot" \
            "/dependabot-options-reference#enable-beta-ecosystems for details."
          )
        end

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

      sig { params(dirname: String).returns(T::Boolean) }
      def should_skip_directory?(dirname)
        SKIP_DIRECTORIES.any? { |skip_dir| dirname.start_with?(skip_dir) }
      end

      # Fetches files referenced in MODULE.bazel files via lock_file and requirements_lock attributes.
      # Also fetches BUILD/BUILD.bazel files from directories containing referenced files, as these
      # are required by Bazel to recognize the directories as valid packages.
      #
      # For local_path_override directories, also fetches MODULE.bazel or WORKSPACE files as Bazel
      # requires these to identify the directory as a valid Bazel module/workspace.
      #
      # Additionally fetches .bzl files referenced in use_extension() and use_repo_rule() calls,
      # along with BUILD files from their directories to make them valid Bazel packages.
      #
      # This method handles Bazel label syntax and converts it to filesystem paths:
      # - "@repo//path:file.json" -> "path/file.json"
      # - "//path:file.json" -> "path/file.json"
      # - "@repo//:file.json" -> "file.json"
      #
      # @return [Array<DependencyFile>] referenced files and their associated BUILD files
      sig { returns(T::Array[DependencyFile]) }
      def referenced_files_from_modules
        files = T.let([], T::Array[DependencyFile])
        directories_with_files = T.let(Set.new, T::Set[String])
        local_override_directories = T.let(Set.new, T::Set[String])

        module_files.each do |module_file|
          file_paths, directory_paths, bzl_file_paths = extract_referenced_paths(module_file)

          files += fetch_paths_and_track_directories(file_paths, directories_with_files)
          files += fetch_paths_and_track_directories(bzl_file_paths, directories_with_files)

          # Track directories from local_path_override for comprehensive fetching
          directory_paths.each { |dir| local_override_directories.add(dir) unless dir == "." }
        end

        files += fetch_build_files_for_directories(directories_with_files)
        files += fetch_local_override_directory_trees(local_override_directories)

        files
      end

      # Fetches files at the given paths and tracks their parent directories.
      # Adds parent directories to the given set for later BUILD file fetching.
      # For .bzl files, recursively fetches their load() dependencies.
      #
      # @param paths [Array<String>] file paths to fetch
      # @param directories [Set<String>] set to track directories for BUILD file fetching
      # @param visited_bzl_files [Set<String>] set to track visited .bzl files to avoid infinite loops
      # @return [Array<DependencyFile>] successfully fetched files
      sig do
        params(
          paths: T::Array[String],
          directories: T::Set[String],
          visited_bzl_files: T::Set[String]
        ).returns(T::Array[DependencyFile])
      end
      def fetch_paths_and_track_directories(paths, directories, visited_bzl_files = Set.new)
        files = T.let([], T::Array[DependencyFile])
        paths.each do |path|
          # Skip if we've already processed this .bzl file
          next if path.end_with?(".bzl") && visited_bzl_files.include?(path)

          fetched_file = fetch_file_if_present(path)
          next unless fetched_file

          files << fetched_file
          dir = File.dirname(path)
          directories.add(dir) unless dir == "."

          # Recursively fetch dependencies for .bzl files
          next unless path.end_with?(".bzl")

          visited_bzl_files.add(path)
          bzl_deps = extract_bzl_load_dependencies(T.must(fetched_file.content), path)
          files += fetch_paths_and_track_directories(bzl_deps, directories, visited_bzl_files)
        end
        files
      end

      # Fetches BUILD or BUILD.bazel files for the given directories.
      #
      # @param directories [Set<String>] directories to fetch BUILD files for
      # @return [Array<DependencyFile>] BUILD files that were found
      sig { params(directories: T::Set[String]).returns(T::Array[DependencyFile]) }
      def fetch_build_files_for_directories(directories)
        files = T.let([], T::Array[DependencyFile])
        directories.each do |dir|
          build_file = fetch_file_if_present("#{dir}/BUILD") || fetch_file_if_present("#{dir}/BUILD.bazel")
          files << build_file if build_file
        end
        files
      end

      # Fetches entire directory trees for local_path_override directories.
      #
      # @param directories [Set<String>] local override directories to fetch recursively
      # @return [Array<DependencyFile>] all files from the directory trees
      sig { params(directories: T::Set[String]).returns(T::Array[DependencyFile]) }
      def fetch_local_override_directory_trees(directories)
        files = T.let([], T::Array[DependencyFile])
        directories.each { |dir| files += fetch_directory_tree(dir) }
        files
      end

      # Extracts file paths from lock_file, requirements_lock, patches, and path attributes in MODULE.bazel.
      # Converts Bazel label syntax to filesystem paths.
      #
      # Bazel labels can have several formats:
      # - "@repo//path:file" - external or self-referential repository with path
      # - "//path:file" - main repository reference with path
      # - "@repo//:file" - external or self-referential repository root file
      # - "//:file" - main repository root file
      #
      # The method:
      # 1. Strips optional @repo prefix
      # 2. Converts colon separators to forward slashes (path:file -> path/file)
      # 3. Removes leading slashes to create relative paths
      # 4. Handles both single files and arrays of files (e.g., patches = ["file1", "file2"])
      # 5. Separates directory paths (from local_path_override) from file paths
      # 6. Extracts .bzl files from use_extension() and use_repo_rule() calls
      #
      # @param module_file [DependencyFile] the MODULE.bazel file to parse
      # @return [Array<Array<String>, Array<String>, Array<String>>] tuple of
      #   [file_paths, directory_paths, bzl_file_paths]
      sig { params(module_file: DependencyFile).returns([T::Array[String], T::Array[String], T::Array[String]]) }
      def extract_referenced_paths(module_file)
        content = T.must(module_file.content)

        file_paths = extract_file_attribute_paths(content)
        directory_paths = extract_directory_paths(content)
        bzl_file_paths = extract_bzl_file_paths(content)

        [file_paths.uniq, directory_paths.uniq, bzl_file_paths.uniq]
      end

      # Extracts file paths from lock_file, requirements_lock, and patches attributes.
      #
      # @param content [String] the MODULE.bazel file content
      # @return [Array<String>] extracted file paths
      sig { params(content: String).returns(T::Array[String]) }
      def extract_file_attribute_paths(content)
        paths = []

        # Match lock_file attributes with optional @repo prefix
        content.scan(%r{lock_file\s*=\s*"(?:@[^"/]+)?//([^"]+)"}) do |match|
          paths << match[0].tr(":", "/").sub(%r{^/}, "")
        end

        # Match requirements_lock attributes with optional @repo prefix
        content.scan(%r{requirements_lock\s*=\s*"(?:@[^"/]+)?//([^"]+)"}) do |match|
          paths << match[0].tr(":", "/").sub(%r{^/}, "")
        end

        # Match patches attribute (can be single file or array)
        content.scan(/patches\s*=\s*\[(.*?)\]/m) do |match|
          match[0].scan(%r{"(?:@[^"/]+)?//([^"]+)"}) do |file_match|
            paths << file_match[0].tr(":", "/").sub(%r{^/}, "")
          end
        end

        paths
      end

      # Extracts directory paths from local_path_override path attributes.
      #
      # @param content [String] the MODULE.bazel file content
      # @return [Array<String>] extracted directory paths
      sig { params(content: String).returns(T::Array[String]) }
      def extract_directory_paths(content)
        paths = []

        # Match path attribute for local_path_override
        content.scan(/path\s*=\s*"([^"]+)"/) do |match|
          path = match[0]
          # Only include if it looks like a local relative path (not a URL or absolute path)
          unless path.start_with?("http://", "https://", "/")
            paths << path.sub(%r{^\./}, "") # Remove leading "./" if present
          end
        end

        paths
      end

      # Extracts .bzl file paths from use_extension() and use_repo_rule() calls.
      # Only extracts files from the local repository (paths starting with "//" without @repo prefix).
      # Skips external repository references (e.g., "@rules_python//...").
      #
      # @param content [String] the MODULE.bazel file content
      # @return [Array<String>] extracted .bzl file paths from local repository only
      sig { params(content: String).returns(T::Array[String]) }
      def extract_bzl_file_paths(content)
        paths = []

        # Extract .bzl files from use_extension() calls (only local repository)
        # Match: use_extension("//path:file.bzl", ...)
        # Skip: use_extension("@external_repo//path:file.bzl", ...)
        content.scan(%r{use_extension\s*\(\s*"//([^"]+)"}) do |match|
          path = match[0].tr(":", "/").sub(%r{^/}, "")
          paths << path if path.end_with?(".bzl")
        end

        # Extract .bzl files from use_repo_rule() calls (only local repository)
        # Match: use_repo_rule("//path:file.bzl", ...)
        # Skip: use_repo_rule("@external_repo//path:file.bzl", ...)
        content.scan(%r{use_repo_rule\s*\(\s*"//([^"]+)"}) do |match|
          path = match[0].tr(":", "/").sub(%r{^/}, "")
          paths << path if path.end_with?(".bzl")
        end

        paths
      end

      # Extracts file dependencies from load() and Label() statements in a .bzl file.
      # Only extracts files from the local repository (paths starting with "//" or ":").
      # Skips external repository references (e.g., "@rules_python//...").
      #
      # @param content [String] the .bzl file content
      # @param file_path [String] the path of the file being parsed (for resolving relative paths)
      # @return [Array<String>] extracted file paths from local repository only
      sig { params(content: String, file_path: String).returns(T::Array[String]) }
      def extract_bzl_load_dependencies(content, file_path)
        paths = []
        file_dir = File.dirname(file_path)

        # Extract files from load() statements (only local repository)
        # Match: load("//path:file.bzl", ...) or load(":file.bzl", ...)
        # Skip: load("@external_repo//path:file.bzl", ...)
        content.scan(%r{load\s*\(\s*"(//[^"]+|:[^"]+)"}) do |match|
          path = resolve_bazel_path(match[0], file_dir)
          paths << path if path
        end

        # Extract files from Label() references (only local repository)
        # Match: Label("//path:file") or Label(":file")
        # Skip: Label("@external_repo//path:file")
        content.scan(%r{Label\s*\(\s*"(//[^"]+|:[^"]+)"\)}) do |match|
          path = resolve_bazel_path(match[0], file_dir)
          paths << path if path
        end

        paths
      end

      # Resolves a Bazel path (from load() or Label()) to a filesystem path.
      # Handles both absolute (//path:file) and relative (:file) paths.
      #
      # @param bazel_path [String] the Bazel path to resolve
      # @param file_dir [String] the directory of the file containing the reference
      # @return [String, nil] the resolved filesystem path, or nil if invalid
      sig { params(bazel_path: String, file_dir: String).returns(T.nilable(String)) }
      def resolve_bazel_path(bazel_path, file_dir)
        if bazel_path.start_with?(":")
          # Convert :file (same directory) to dir/file
          relative_file = bazel_path.sub(/^:/, "")
          file_dir == "." ? relative_file : "#{file_dir}/#{relative_file}"
        elsif bazel_path.start_with?("//")
          # Convert //path:file to path/file
          bazel_path.tr(":", "/").sub(%r{^/+}, "")
        end
      end

      # Recursively fetches all files in a directory tree.
      # This is used for local_path_override directories which need comprehensive file access
      # as they are local modules that may have complex internal structures.
      #
      # @param directory [String] the directory path to fetch recursively
      # @return [Array<DependencyFile>] all files found in the directory tree
      sig { params(directory: String).returns(T::Array[DependencyFile]) }
      def fetch_directory_tree(directory)
        files = T.let([], T::Array[DependencyFile])

        # Fetch the directory listing to see what's inside
        listing = repo_contents(dir: directory)

        listing.each do |item|
          item_path = "#{directory}/#{item.name}"

          if item.type == "dir"
            # Recursively fetch subdirectories
            files += fetch_directory_tree(item_path)
          elsif item.type == "file"
            # Fetch individual files
            fetched_file = fetch_file_if_present(item_path)
            files << fetched_file if fetched_file
          end
        rescue Dependabot::DependencyFileNotFound, Octokit::NotFound
          # Skip files/directories that can't be accessed
          Dependabot.logger.debug("Skipping inaccessible item: #{item_path}")
        end

        files
      rescue Octokit::NotFound, Dependabot::DependencyFileNotFound
        # Directory doesn't exist or is inaccessible - log and return empty array
        Dependabot.logger.debug("Directory not found or inaccessible: #{directory}")
        []
      end

      # Fetches downloader_config files referenced in .bazelrc.
      # Parses .bazelrc for lines like "--downloader_config=FILENAME" and fetches those files.
      #
      # @return [Array<DependencyFile>] downloader config files referenced in .bazelrc
      sig { returns(T::Array[DependencyFile]) }
      def downloader_config_files
        files = T.let([], T::Array[DependencyFile])
        bazelrc_file = fetch_file_if_present(".bazelrc")
        return files unless bazelrc_file

        config_paths = extract_downloader_config_paths(bazelrc_file)
        config_paths.each do |path|
          config_file = fetch_file_if_present(path)
          files << config_file if config_file
        rescue Dependabot::DependencyFileNotFound
          Dependabot.logger.warn(
            "Downloader config file '#{path}' referenced in .bazelrc but not found in repository"
          )
        end

        files
      end

      # Extracts downloader_config file paths from .bazelrc content.
      # Matches lines containing --downloader_config=FILENAME.
      #
      # @param bazelrc_file [DependencyFile] the .bazelrc file to parse
      # @return [Array<String>] unique relative file paths for downloader configs
      sig { params(bazelrc_file: DependencyFile).returns(T::Array[String]) }
      def extract_downloader_config_paths(bazelrc_file)
        content = T.must(bazelrc_file.content)
        paths = []

        # Match --downloader_config=FILENAME patterns
        # This handles various formats:
        # - --downloader_config=path/to/file.json
        # - --downloader_config path/to/file.json
        # - build --downloader_config=path/to/file.json
        content.scan(/--downloader_config[=\s]+(\S+)/) do |match|
          path = match[0]
          paths << path unless path.empty?
        end

        paths.uniq
      end
    end
  end
end

Dependabot::FileFetchers.register("bazel", Dependabot::Bazel::FileFetcher)
