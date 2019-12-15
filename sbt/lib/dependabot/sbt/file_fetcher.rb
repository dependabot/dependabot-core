# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

module Dependabot
  module Sbt
    class FileFetcher < Dependabot::FileFetchers::Base
      def self.required_files_in?(_filename_array)
        filenames.include?("build.sbt")
      end

      def self.required_files_message
        "Repo must contain a build.sbt."
      end

      private

      def fetch_files
        fetched_files = []
        fetched_files << buildfile
        fetched_files += all_files_in_project_directory
        fetched_files
      end

      def buildfile
        @buildfile ||= fetch_file_from_host("build.sbt")
      end

      def all_files_in_project_directory
        files = project_directory_listing
        return [] unless files

        files.select { |f| %w(.sbt .scala).include? File.extname(f.name) }.
          map { |f| fetch_file_from_host(f.path) }
      end

      def project_directory_listing
        repo_contents(dir: "project", raise_errors: true)
      rescue *CLIENT_NOT_FOUND_ERRORS
        nil
      end
    end
  end
end

Dependabot::FileFetchers.register("sbt", Dependabot::Sbt::FileFetcher)
