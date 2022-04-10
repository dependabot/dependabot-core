# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

module Dependabot
  module CocoaPods
    # Fetches the Podfile and Podfile.lock files within directory
    class FileFetcher < Dependabot::FileFetchers::Base
      def self.required_files_in?(filenames)
        (%w(Podfile Podfile.lock) - filenames).empty?
      end

      def self.required_files_message
        "Repo must contain a Podfile and a Podfile.lock."
      end

      private

      def fetch_files
        fetched_files = []
        fetched_files << podfile
        fetched_files << lockfile
        fetched_files
      end

      def podfile
        @podfile ||= fetch_file_from_host("Podfile")
      end

      def lockfile
        @lockfile ||= fetch_file_from_host("Podfile.lock")
      end
    end
  end
end

Dependabot::FileFetchers.
  register("cocoapods", Dependabot::CocoaPods::FileFetcher)
