# frozen_string_literal: true

require "dependabot/file_fetchers/base"

module Dependabot
  module FileFetchers
    module Php
      class Composer < Dependabot::FileFetchers::Base
        def self.required_files_in?(filenames)
          filenames.include?("composer.json")
        end

        def self.required_files_message
          "Repo must contain a composer.json."
        end

        private

        def fetch_files
          fetched_files = []
          fetched_files << composer_json
          fetched_files << composer_lock if composer_lock
          fetched_files
        end

        def composer_json
          @composer_json ||= fetch_file_from_host("composer.json")
        end

        def composer_lock
          @composer_lock ||= fetch_file_from_host("composer.lock")
        rescue Dependabot::DependencyFileNotFound
          nil
        end
      end
    end
  end
end
