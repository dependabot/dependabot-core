# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"
require "dependabot/file_filtering"

module Dependabot
  module Gradle
    class FileFetcher < Dependabot::FileFetchers::Base
      extend T::Sig
      extend T::Helpers

      require_relative "file_parser"
      require_relative "file_fetcher/settings_file_parser"

      SUPPORTED_LOCK_FILE_NAMES = T.let(%w(gradle.lockfile).freeze, T::Array[String])

      SUPPORTED_BUILD_FILE_NAMES =
        T.let(%w(build.gradle build.gradle.kts).freeze, T::Array[String])

      SUPPORTED_SETTINGS_FILE_NAMES =
        T.let(%w(settings.gradle settings.gradle.kts).freeze, T::Array[String])

      # For now Gradle only supports library .toml files in the main gradle folder
      SUPPORTED_VERSION_CATALOG_FILE_PATH =
        T.let(%w(/gradle/libs.versions.toml).freeze, T::Array[String])

      sig do
        override
          .params(
            source: Dependabot::Source,
            credentials: T::Array[Dependabot::Credential],
            repo_contents_path: T.nilable(String),
            options: T::Hash[String, String],
            update_config: T.nilable(Dependabot::Config::UpdateConfig)
          )
          .void
      end
      def initialize(source:, credentials:, repo_contents_path: nil, options: {}, update_config: nil)
        super

        @lockfile_name = T.let(T.must(SUPPORTED_LOCK_FILE_NAMES.first), String)
        @buildfile_name = T.let(nil, T.nilable(String))
      end

      sig { override.params(filenames: T::Array[String]).returns(T::Boolean) }
      def self.required_files_in?(filenames)
        filenames.any? do |filename|
          SUPPORTED_BUILD_FILE_NAMES.any? { |supported| filename.end_with?(supported) }
        end
      end

      sig { override.returns(String) }
      def self.required_files_message
        "Repo must contain a build.gradle / build.gradle.kts file."
      end

      sig { override.returns(T::Array[DependencyFile]) }
      def fetch_files
        fetched_files = all_buildfiles_in_build(".")

        # Filter excluded files from final collection
        filtered_files = fetched_files.reject do |file|
          Dependabot::FileFiltering.should_exclude_path?(file.name, "file from final collection", @exclude_paths)
        end

        filtered_files
      end

      private

      sig { params(root_dir: String).returns(T::Array[DependencyFile]) }
      def all_buildfiles_in_build(root_dir)
        files = [buildfile(root_dir), settings_file(root_dir), version_catalog_file(root_dir), lockfile(root_dir)]
                .compact
        files += subproject_buildfiles(root_dir)
        files += subproject_lockfiles(root_dir)
        files += dependency_script_plugins(root_dir)
        files + included_builds(root_dir)
                .flat_map { |dir| all_buildfiles_in_build(dir) }
      end

      sig { params(root_dir: String).returns(T::Array[String]) }
      def included_builds(root_dir)
        builds = []

        # buildSrc is implicit: included but not declared in settings.gradle
        buildsrc = repo_contents(dir: root_dir, raise_errors: false)
                   .find { |item| item.type == "dir" && item.name == "buildSrc" }
        builds << clean_join([root_dir, "buildSrc"]) if buildsrc

        return builds unless settings_file(root_dir)

        builds += SettingsFileParser
                  .new(settings_file: T.must(settings_file(root_dir)))
                  .included_build_paths
                  .map { |p| clean_join([root_dir, p]) }

        builds.uniq
      end

      sig { params(parts: T::Array[String]).returns(String) }
      def clean_join(parts)
        Pathname.new(File.join(parts)).cleanpath.to_path
      end

      sig { params(root_dir: String).returns(T::Array[DependencyFile]) }
      def subproject_lockfiles(root_dir)
        return [] unless settings_file(root_dir)

        subproject_paths =
          SettingsFileParser
          .new(settings_file: T.must(settings_file(root_dir)))
          .subproject_paths

        subproject_paths.filter_map do |path|
          lockfile_path = File.join(root_dir, path, @lockfile_name)

          # Skip excluded subproject lockfiles
          next nil if Dependabot::FileFiltering.should_exclude_path?(lockfile_path,
                                                                     "subproject lockfile in subproject '#{path}'",
                                                                     @exclude_paths)

          fetch_file_from_host(lockfile_path)
        rescue Dependabot::DependencyFileNotFound
          # Gradle itself doesn't worry about missing subprojects, so we don't
          nil
        end
      end

      sig { params(root_dir: String).returns(T::Array[DependencyFile]) }
      def subproject_buildfiles(root_dir)
        return [] unless settings_file(root_dir)

        subproject_paths =
          SettingsFileParser
          .new(settings_file: T.must(settings_file(root_dir)))
          .subproject_paths

        subproject_paths.filter_map do |path|
          if @buildfile_name
            buildfile_path = File.join(root_dir, path, @buildfile_name)

            # Skip excluded subproject buildfiles
            next nil if Dependabot::FileFiltering.should_exclude_path?(buildfile_path,
                                                                       "subproject buildfile in subproject '#{path}'",
                                                                       @exclude_paths)

            fetch_file_from_host(buildfile_path)
          else
            subproject_dir = File.join(root_dir, path)

            # Skip excluded subproject directories
            next nil if Dependabot::FileFiltering.should_exclude_path?(subproject_dir,
                                                                       "subproject directory for subproject '#{path}'",
                                                                       @exclude_paths)

            buildfile(subproject_dir)
          end
        rescue Dependabot::DependencyFileNotFound
          # Gradle itself doesn't worry about missing subprojects, so we don't
          nil
        end
      end

      sig { params(root_dir: String).returns(T.nilable(DependencyFile)) }
      def version_catalog_file(root_dir)
        return nil unless root_dir == "."

        gradle_toml_file(root_dir)
      end

      # rubocop:disable Metrics/PerceivedComplexity
      sig { params(root_dir: String).returns(T::Array[DependencyFile]) }
      def dependency_script_plugins(root_dir)
        return [] unless buildfile(root_dir)

        dependency_plugin_paths =
          FileParser.find_include_names(buildfile(root_dir))
                    .reject { |path| path.include?("://") }
                    .reject { |path| !path.include?("/") && path.split(".").count > 2 }
                    .select { |filename| filename.include?("dependencies") }
                    .map { |path| path.gsub("$rootDir", ".") }
                    .map { |path| File.join(root_dir, path) }
                    .uniq

        dependency_plugin_paths.filter_map do |path|
          # Skip excluded dependency script plugins
          next nil if Dependabot::FileFiltering.should_exclude_path?(path,
                                                                     "dependency script plugin",
                                                                     @exclude_paths)

          fetch_file_from_host(path)
        rescue Dependabot::DependencyFileNotFound
          next nil if file_exists_in_submodule?(path)
          next nil if path.include?("${")

          raise
        end
      end
      # rubocop:enable Metrics/PerceivedComplexity

      sig { params(path: T.any(Pathname, String)).returns(T::Boolean) }
      def file_exists_in_submodule?(path)
        fetch_file_from_host(path, fetch_submodules: true)
        true
      rescue Dependabot::DependencyFileNotFound
        false
      end

      sig { params(dir: String).returns(T.nilable(DependencyFile)) }
      def lockfile(dir)
        fetch_file_if_present(File.join(dir, @lockfile_name))
      end

      sig { params(dir: String).returns(T.nilable(DependencyFile)) }
      def buildfile(dir)
        file = find_first(dir, SUPPORTED_BUILD_FILE_NAMES) || return
        @buildfile_name ||= File.basename(file.name)
        file
      end

      sig { params(dir: String).returns(T.nilable(DependencyFile)) }
      def gradle_toml_file(dir)
        find_first(dir, SUPPORTED_VERSION_CATALOG_FILE_PATH)
      end

      sig { params(dir: String).returns(T.nilable(DependencyFile)) }
      def settings_file(dir)
        find_first(dir, SUPPORTED_SETTINGS_FILE_NAMES)
      end

      sig { params(dir: String, supported_names: T::Array[String]).returns(T.nilable(DependencyFile)) }
      def find_first(dir, supported_names)
        paths = supported_names
                .map { |name| clean_join([dir, name]) }
                .each do |path|
          return cached_files[path] || next
        end
        fetch_first_if_present(paths)
      end

      sig { returns(T::Hash[String, DependencyFile]) }
      def cached_files
        @cached_files ||= T.let({}, T.nilable(T::Hash[String, DependencyFile]))
      end

      sig { params(paths: T::Array[String]).returns(T.nilable(DependencyFile)) }
      def fetch_first_if_present(paths)
        paths.each do |path|
          file = fetch_file_if_present(path) || next
          cached_files[path] = file
          return file
        end
        nil
      end
    end
  end
end

Dependabot::FileFetchers.register("gradle", Dependabot::Gradle::FileFetcher)
