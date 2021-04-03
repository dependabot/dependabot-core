# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

module Dependabot
  module Pub
    class FileFetcher < Dependabot::FileFetchers::Base
      def self.required_files_in?(filenames)
        filenames.include?("pubspec.yaml")
      end

      def self.required_files_message
        "Repo must contain a pubspec.yaml configuration file."
      end

      private

      def fetch_files
        fetched_files = []
        fetched_files << pubspec_yaml if pubspec_yaml
        fetched_files << pubspec_lock if pubspec_lock

        check_required_files_present

        return fetched_files if fetched_files.any?
      end

      def pubspec_yaml
        @pubspec_yaml ||= fetch_file_from_host("pubspec.yaml")
      end

      def pubspec_lock
        @pubspec_lock ||= fetch_file_from_host("pubspec.lock")
      end

      def check_required_files_present
        return if pubspec_yaml

        path = Pathname.new(File.join(directory, "pubspec.yaml")).
               cleanpath.to_path
        raise Dependabot::DependencyFileNotFound, path
      end
    end
  end
end

Dependabot::FileFetchers.
  register("pub", Dependabot::Pub::FileFetcher)
