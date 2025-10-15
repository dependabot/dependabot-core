# typed: strict
# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

module Dependabot
  module Bazel
    class FileFetcher < Dependabot::FileFetchers::Base
      extend T::Sig

      WORKSPACE_FILES = T.let(%w(WORKSPACE WORKSPACE.bazel).freeze, T::Array[String])
      MODULE_FILES = T.let(%w(MODULE.bazel).freeze, T::Array[String])
      BUILD_FILES = T.let(%w(BUILD BUILD.bazel).freeze, T::Array[String])
      CONFIG_FILES = T.let(%w(.bazelrc MODULE.bazel.lock).freeze, T::Array[String])
      SKIP_DIRECTORIES = T.let(%w(.git .bazel-* bazel-* node_modules .github).freeze, T::Array[String])

      sig { override.returns(String) }
      def self.required_files_message
        "Repo must contain a WORKSPACE, WORKSPACE.bazel, or MODULE.bazel file."
      end

      sig { override.params(filenames: T::Array[String]).returns(T::Boolean) }
      def self.required_files_in?(filenames)
        filenames.any? { |name| WORKSPACE_FILES.include?(name) || MODULE_FILES.include?(name) }
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
        fetched_files += build_files
        fetched_files += config_files

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

        MODULE_FILES.each do |filename|
          file = fetch_file_if_present(filename)
          files << file if file
        end

        files
      end

      sig { returns(T::Array[DependencyFile]) }
      def build_files
        files = T.let([], T::Array[DependencyFile])

        BUILD_FILES.each do |filename|
          file = fetch_file_if_present(filename)
          files << file if file
        end

        files += fetch_build_files_from_subdirectories

        files
      end

      sig { returns(T::Array[DependencyFile]) }
      def config_files
        files = T.let([], T::Array[DependencyFile])

        CONFIG_FILES.each do |filename|
          file = fetch_file_if_present(filename)
          files << file if file
        end

        bazelversion = fetch_file_if_present(".bazelversion")
        files << bazelversion if bazelversion

        files
      end

      sig { returns(T::Array[DependencyFile]) }
      def fetch_build_files_from_subdirectories
        files = T.let([], T::Array[DependencyFile])

        repo_contents.select { |item| item.type == "dir" }.each do |dir|
          next if should_skip_directory?(dir.name)

          BUILD_FILES.each do |build_filename|
            build_file_path = File.join(dir.name, build_filename)

            file = fetch_file_from_host(build_file_path)
            files << file if file
          end
        end

        files
      end

      sig { params(dirname: String).returns(T::Boolean) }
      def should_skip_directory?(dirname)
        SKIP_DIRECTORIES.any? { |skip_dir| dirname.start_with?(skip_dir) }
      end
    end
  end
end

Dependabot::FileFetchers.register("bazel", Dependabot::Bazel::FileFetcher)
