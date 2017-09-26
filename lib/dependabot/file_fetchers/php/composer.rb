# frozen_string_literal: true

require "dependabot/file_fetchers/base"

module Dependabot
  module FileFetchers
    module Php
      class Composer < Dependabot::FileFetchers::Base
        def self.required_files_in?(filenames)
          (%w(composer.json composer.lock) - filenames).empty?
        end

        def self.required_files_message
          "Repo must contain a composer.json and a composer.lock."
        end

        private

        def fetch_files
          fetched_files = []
          fetched_files << composer_json
          fetched_files << composer_lock
          fetched_files
        end

        def composer_json
          @composer_json ||= fetch_file_from_github("composer.json")
        end

        def composer_lock
          @composer_lock ||= fetch_file_from_github("composer.lock")
        end
      end
    end
  end
end
