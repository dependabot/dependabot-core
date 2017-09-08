# frozen_string_literal: true
require "dependabot/file_fetchers/base"

module Dependabot
  module FileFetchers
    module Git
      class Submodules < Dependabot::FileFetchers::Base
        def self.required_files_in?(filenames)
          filenames.include?(".gitmodules")
        end

        def self.required_files_message
          "Repo must contain a .gitmodules file."
        end

        private

        def fetch_files
          [gitmodules_file]
        end

        def gitmodules_file
          @gitmodules_file ||= fetch_file_from_github(".gitmodules")
        end
      end
    end
  end
end
