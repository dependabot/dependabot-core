# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

module Dependabot
  module Gradle
    class FileFetcher < Dependabot::FileFetchers::Base
      require_relative "file_fetcher/settings_file_parser"

      SUPPORTED_BUILD_FILE_NAMES =
        %w(build.gradle build.gradle.kts).freeze

      SUPPORTED_SETTINGS_FILE_NAMES =
        %w(settings.gradle settings.gradle.kts).freeze

      def self.required_files_in?(filenames)
        filenames.any? do |filename|
          SUPPORTED_BUILD_FILE_NAMES.include?(filename)
        end
      end

      def self.required_files_message
        "Repo must contain a build.gradle / build.gradle.kts file."
      end

      private

      def fetch_files
        dir = "."
        fetched_files = [buildfile(dir), settings_file(dir)].compact
        fetched_files += subproject_buildfiles(dir)
        fetched_files += dependency_script_plugins(dir)
        check_required_files_present(fetched_files)
        fetched_files
      end

      def subproject_buildfiles(root_dir)
        return [] unless settings_file(root_dir)

        @subproject_buildfiles ||= begin
          subproject_paths =
            SettingsFileParser.
            new(settings_file: settings_file(root_dir)).
            subproject_paths

          subproject_paths.filter_map do |path|
            if @buildfile_name
              fetch_file_from_host(File.join(path, @buildfile_name))
            else
              buildfile(path)
            end
          rescue Dependabot::DependencyFileNotFound
            # Gradle itself doesn't worry about missing subprojects, so we don't
            nil
          end
        end
      end

      # rubocop:disable Metrics/PerceivedComplexity
      def dependency_script_plugins(root_dir)
        return [] unless buildfile(root_dir)

        dependency_plugin_paths =
          FileParser.find_include_names(buildfile(root_dir)).
          reject { |path| path.include?("://") }.
          reject { |path| !path.include?("/") && path.split(".").count > 2 }.
          select { |filename| filename.include?("dependencies") }.
          map { |path| path.gsub("$rootDir", ".") }.
          uniq

        dependency_plugin_paths.filter_map do |path|
          fetch_file_from_host(path)
        rescue Dependabot::DependencyFileNotFound
          next nil if file_exists_in_submodule?(path)
          next nil if path.include?("${")

          raise
        end
      end
      # rubocop:enable Metrics/PerceivedComplexity

      def check_required_files_present(files)
        return if files.any?

        path = Pathname.new(File.join(directory, "build.gradle")).cleanpath.to_path
        path += "(.kts)?"
        raise Dependabot::DependencyFileNotFound, path
      end

      def file_exists_in_submodule?(path)
        fetch_file_from_host(path, fetch_submodules: true)
        true
      rescue Dependabot::DependencyFileNotFound
        false
      end

      def buildfile(dir)
        file = first_present_file(dir, SUPPORTED_BUILD_FILE_NAMES)
        @buildfile_name = file.name if file
        file
      end

      def settings_file(dir)
        first_present_file(dir, SUPPORTED_SETTINGS_FILE_NAMES)
      end

      def first_present_file(dir, supported_names)
        paths = supported_names.map { |name| File.join(dir, name) }
        paths.each do |path|
          return cache[path] if cache.include? path
        end
        fetch_first_present_file(paths)
      end

      def cache
        @cached_files ||= Hash.new
      end

      def fetch_first_present_file(paths)
        paths.each do |path|
          file = fetch_file_if_present(path)
          if file
            cache[path] = file
            return file
          end
        end
        nil
      end
    end
  end
end

Dependabot::FileFetchers.register("gradle", Dependabot::Gradle::FileFetcher)
