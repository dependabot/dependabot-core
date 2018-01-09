# frozen_string_literal: true

require "dependabot/file_fetchers/base"

module Dependabot
  module FileFetchers
    module CSharp
      class Nuget < Dependabot::FileFetchers::Base
        def self.required_files_in?(filenames)
          (%w(paket.dependencies paket.lock) - filenames).empty?
        end

        def self.required_files_message
          "Repo must contain a paket.dependencies and paket.lock."
        end

        private

        def fetch_files
          fetched_files = []
          fetched_files << dependencies_file
          fetched_files << lockfile
          fetched_files
        end

        def dependencies_file
          # Fetching files is easy - the base class provides a
          # fetch_file_from_github method that just needs a filename
          @dependencies_file ||= fetch_file_from_github("paket.dependencies")
        end

        def lockfile
          @lockfile ||= fetch_file_from_github("paket.lock")
        end
      end
    end
  end
end
