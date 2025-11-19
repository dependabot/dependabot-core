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

        module_files.each do |module_file|
          referenced_paths = extract_referenced_paths(module_file)

          referenced_paths.each do |path|
            fetched_file = fetch_file_if_present(path)
            next unless fetched_file

            files << fetched_file
            # Track directories that contain referenced files so we can fetch their BUILD files.
            # Exclude root directory (.) as BUILD files there are already handled by config_files.
            dir = File.dirname(path)
            directories_with_files.add(dir) unless dir == "."
          end
        end

        # Fetch BUILD or BUILD.bazel files for directories that contain referenced files.
        # These BUILD files are required for Bazel to recognize directories as valid packages.
        directories_with_files.each do |dir|
          build_file = fetch_file_if_present("#{dir}/BUILD") || fetch_file_if_present("#{dir}/BUILD.bazel")
          files << build_file if build_file
        end

        files
      end

      # Extracts file paths from lock_file and requirements_lock attributes in MODULE.bazel content.
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
      #
      # @param module_file [DependencyFile] the MODULE.bazel file to parse
      # @return [Array<String>] unique relative file paths referenced in the module
      sig { params(module_file: DependencyFile).returns(T::Array[String]) }
      def extract_referenced_paths(module_file)
        content = T.must(module_file.content)
        paths = []

        # Match lock_file attributes with optional @repo prefix: "(?:@[^"\/]+)?\/\/([^"]+)"
        # Capture group 1: everything after // (e.g., "tools/jol:file.json" or ":file.json")
        content.scan(%r{lock_file\s*=\s*"(?:@[^"/]+)?//([^"]+)"}) do |match|
          path = match[0].tr(":", "/").sub(%r{^/}, "")
          paths << path
        end

        # Match requirements_lock attributes with optional @repo prefix
        content.scan(%r{requirements_lock\s*=\s*"(?:@[^"/]+)?//([^"]+)"}) do |match|
          path = match[0].tr(":", "/").sub(%r{^/}, "")
          paths << path
        end

        paths.uniq
      end
    end
  end
end

Dependabot::FileFetchers.register("bazel", Dependabot::Bazel::FileFetcher)
