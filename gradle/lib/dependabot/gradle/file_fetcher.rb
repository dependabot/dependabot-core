# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

module Dependabot
  module Gradle
    class FileFetcher < Dependabot::FileFetchers::Base
      require_relative "file_fetcher/settings_file_parser"

      def self.required_files_in?(filenames)
        filenames.include?("build.gradle")
      end

      def self.required_files_message
        "Repo must contain a build.gradle."
      end

      private

      def fetch_files
        fetched_files = []
        fetched_files << buildfile
        fetched_files += subproject_buildfiles
        fetched_files += dependency_script_plugins
        fetched_files
      end

      def buildfile
        @buildfile ||= fetch_file_from_host("build.gradle")
      end

      def subproject_buildfiles
        return [] unless settings_file

        subproject_paths =
          SettingsFileParser.
          new(settings_file: settings_file).
          subproject_paths

        subproject_paths.map do |path|
          fetch_file_from_host(File.join(path, "build.gradle"))
        rescue Dependabot::DependencyFileNotFound
          # Gradle itself doesn't worry about missing subprojects, so we don't
          nil
        end.compact
      end

      def dependency_script_plugins
        dependency_plugin_paths =
          buildfile.content.
          scan(/apply from:\s+['"]([^'"]+)['"]/).flatten.
          reject { |path| path.include?("://") }.
          reject { |path| !path.include?("/") && path.split(".").count > 2 }.
          select { |filename| filename.include?("dependencies") }

        dependency_plugin_paths.map do |path|
          fetch_file_from_host(path)
        rescue Dependabot::DependencyFileNotFound
          # Experimental feature - raise an error for Dependabot team to review
          raise "Script plugin not found: #{path}"
        end.compact
      end

      def settings_file
        @settings_file ||= fetch_file_from_host("settings.gradle")
      rescue Dependabot::DependencyFileNotFound
        nil
      end
    end
  end
end

Dependabot::FileFetchers.register("gradle", Dependabot::Gradle::FileFetcher)
