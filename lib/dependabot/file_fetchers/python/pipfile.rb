# frozen_string_literal: true

require "dependabot/file_fetchers/base"

module Dependabot
  module FileFetchers
    module Python
      class Pipfile < Dependabot::FileFetchers::Base
        def self.required_files_in?(filenames)
          (%w(Pipfile Pipfile.lock) - filenames).empty?
        end

        def self.required_files_message
          "Repo must contain a Pipfile and a Pipfile.lock."
        end

        private

        def fetch_files
          fetched_files = []
          fetched_files << pipfile
          fetched_files << lockfile
          fetched_files
        end

        def pipfile
          @pipfile ||= fetch_file_from_github("Pipfile")
        end

        def lockfile
          @lockfile ||= fetch_file_from_github("Pipfile.lock")
        end
      end
    end
  end
end
