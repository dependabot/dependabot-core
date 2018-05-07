# frozen_string_literal: true

require "dependabot/file_fetchers/base"

module Dependabot
  module FileFetchers
    module Java
      class Gradle < Dependabot::FileFetchers::Base
        require_relative "gradle/settings_file_parser"

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
            raise "Couldn't find a Gradle file. Investigate!"
          end
        end

        def settings_file
          @settings_file ||= fetch_file_from_host("settings.gradle")
        rescue Dependabot::DependencyFileNotFound
          nil
        end
      end
    end
  end
end
