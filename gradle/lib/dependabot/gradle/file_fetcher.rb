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
        fetched_files = []
        fetched_files << buildfile if buildfile
        fetched_files << settings_file if settings_file
        fetched_files += subproject_buildfiles
        fetched_files += dependency_script_plugins
        check_required_files_present
        fetched_files
      end

      def buildfile
        @buildfile ||= begin
          file = supported_build_file
          @buildfile_name ||= file.name if file
          file
        end
      end

      def subproject_buildfiles
        return [] unless settings_file

        @subproject_buildfiles ||= begin
          subproject_paths =
            SettingsFileParser.
            new(settings_file: settings_file).
            subproject_paths

          subproject_paths.map do |path|
            if @buildfile_name
              fetch_file_from_host(File.join(path, @buildfile_name))
            else
              supported_file(SUPPORTED_BUILD_FILE_NAMES.map { |f| File.join(path, f) })
            end
          rescue Dependabot::DependencyFileNotFound
            # Gradle itself doesn't worry about missing subprojects, so we don't
            nil
          end.compact
        end
      end

      # rubocop:disable Metrics/PerceivedComplexity
      def dependency_script_plugins
        return [] unless buildfile

        dependency_plugin_paths =
          FileParser.find_include_names(buildfile).
          reject { |path| path.include?("://") }.
          reject { |path| !path.include?("/") && path.split(".").count > 2 }.
          select { |filename| filename.include?("dependencies") }.
          map { |path| path.gsub("$rootDir", ".") }.
          uniq

        dependency_plugin_paths.map do |path|
          fetch_file_from_host(path)
        rescue Dependabot::DependencyFileNotFound
          next nil if file_exists_in_submodule?(path)
          next nil if path.include?("${")

          raise
        end.compact
      end
      # rubocop:enable Metrics/PerceivedComplexity

      def check_required_files_present
        return if buildfile || (subproject_buildfiles && !subproject_buildfiles.empty?)

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

      def settings_file
        @settings_file ||= supported_settings_file
      end

      def supported_build_file
        supported_file(SUPPORTED_BUILD_FILE_NAMES)
      end

      def supported_settings_file
        supported_file(SUPPORTED_SETTINGS_FILE_NAMES)
      end

      def supported_file(supported_file_names)
        supported_file_names.each do |supported_file_name|
          file = fetch_file_if_present(supported_file_name)
          return file if file
        end

        nil
      end
    end
  end
end

Dependabot::FileFetchers.register("gradle", Dependabot::Gradle::FileFetcher)
