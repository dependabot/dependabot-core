# frozen_string_literal: true
require "dependabot/file_fetchers/base"

module Dependabot
  module FileFetchers
    module Cocoa
      class CocoaPods < Dependabot::FileFetchers::Base
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
          @podfile ||= fetch_file_from_github("Podfile")
        end

        def lockfile
          @lockfile ||= fetch_file_from_github("Podfile.lock")
        end
      end
    end
  end
end
