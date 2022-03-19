# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

# For details on pub packages, see:
# https://dart.dev/tools/pub/package-layout#the-pubspec
module Dependabot
  module Pub
    class FileFetcher < Dependabot::FileFetchers::Base
      def self.required_files_in?(filenames)
        filenames.include?("pubspec.yaml")
      end

      def self.required_files_message
        "Repo must contain a pubspec.yaml."
      end

      private

      def fetch_files
        fetched_files = []
        fetched_files << pubspec_yaml
        fetched_files << pubspec_lock if pubspec_lock
        # Fetch any additional pubspec.yamls in the same git repo for resolving
        # local path-dependencies.
        extra_pubspecs = Dir.glob("**/pubspec.yaml", base: clone_repo_contents)
        fetched_files += extra_pubspecs.map do |pubspec|
          relative_name = Pathname.new("/#{pubspec}").relative_path_from(directory)
          fetch_file_from_host(relative_name)
        end
        fetched_files.uniq
      end

      def pubspec_yaml
        @pubspec_yaml ||= fetch_file_from_host("pubspec.yaml")
      end

      def pubspec_lock
        @pubspec_lock ||= fetch_file_if_present("pubspec.lock")
      end
    end
  end
end

Dependabot::FileFetchers.register("pub", Dependabot::Pub::FileFetcher)
