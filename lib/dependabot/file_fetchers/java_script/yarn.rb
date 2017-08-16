# frozen_string_literal: true
require "dependabot/file_fetchers/base"

module Dependabot
  module FileFetchers
    module JavaScript
      class Yarn < Dependabot::FileFetchers::Base
        def self.required_files_in?(filenames)
          (%w(package.json yarn.lock) - filenames).empty?
        end

        def self.required_files_message
          "Repo must contain a package.json and a yarn.lock."
        end

        private

        def fetch_files
          fetched_files = []
          fetched_files << package_json
          fetched_files << yarn_lock
          fetched_files
        end

        def package_json
          @package_json ||= fetch_file_from_github("package.json")
        end

        def yarn_lock
          @yarn_lock ||= fetch_file_from_github("yarn.lock")
        end
      end
    end
  end
end
