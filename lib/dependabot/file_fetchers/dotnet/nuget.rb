# frozen_string_literal: true

require "dependabot/file_fetchers/base"

module Dependabot
  module FileFetchers
    module Dotnet
      class Nuget < Dependabot::FileFetchers::Base
        def self.required_files_in?(filenames)
          # Check that a list of filenames includes the minimum requirements
          # for doing an update
          (%w(paket.dependencies paket.lock) - filenames).empty?
        end

        def self.required_files_message
          # Error message to serve if `required_files_in?(filenames)` is false
          "Repo must contain a paket.dependencies and paket.lock."
        end

        private

        def fetch_files
          # This method needs to return all of the files that we need to fetch.
          # That means all the files that:
          # - we may need to read in order to figure out what to update
          # - we may wish to change as part of the update
          #
          # You can use the `fetch_file_from_github` helper to get files as
          # long as you know their name. If you need to dynamically figure out
          # what files to fetch, things get harder (the JS file fetcher is a
          # good example)
          fetched_files = []
          fetched_files << example_file
          fetched_files
        end

        def example_file
          @example_file ||= fetch_file_from_github("example.file")
        end
      end
    end
  end
end
