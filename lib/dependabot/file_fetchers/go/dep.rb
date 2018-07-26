# frozen_string_literal: true

require "dependabot/file_fetchers/base"

module Dependabot
  module FileFetchers
    module Go
      class Dep < Dependabot::FileFetchers::Base
        def self.required_files_in?(filenames)
          (%w(Gopkg.toml Gopkg.lock) - filenames).empty?
        end

        def self.required_files_message
          "Repo must contain a Gopkg.toml and Gopkg.lock."
        end

        private

        def fetch_files
          fetched_files = []
          fetched_files << manifest
          fetched_files << lockfile

          # Fetch the main.go file if present, as this will later identify
          # this repo as an app.
          fetched_files << main if main
          fetched_files
        end

        def manifest
          @manifest ||= fetch_file_from_host("Gopkg.toml")
        end

        def lockfile
          @lockfile ||= fetch_file_from_host("Gopkg.lock")
        end

        def main
          fetch_file_if_present("main.go")
        end
      end
    end
  end
end
