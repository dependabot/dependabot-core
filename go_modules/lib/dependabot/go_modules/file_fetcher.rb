# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

module Dependabot
  module GoModules
    class FileFetcher < Dependabot::FileFetchers::Base
      def self.required_files_in?(filenames)
        filenames.include?("go.mod")
      end

      def self.required_files_message
        "Repo must contain a go.mod."
      end

      private

      def fetch_files
        fetched_files = [go_mod]
        # Fetch the (optional) go.sum
        fetched_files << go_sum if go_sum
        fetched_files
      end

      def go_mod
        @go_mod ||= fetch_file_if_present("go.mod")
      end

      def go_sum
        @go_sum ||= fetch_file_if_present("go.sum")
      end

      def recurse_submodules_when_cloning?
        true
      end
    end
  end
end

Dependabot::FileFetchers.
  register("go_modules", Dependabot::GoModules::FileFetcher)
