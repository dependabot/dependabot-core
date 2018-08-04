# frozen_string_literal: true

require "dependabot/file_fetchers/base"

module Dependabot
  module FileFetchers
    module Elm
      class ElmPackage < Dependabot::FileFetchers::Base
        def self.required_files_in?(filenames)
          filenames.include?("elm-package.json")
        end

        def self.required_files_message
          "Repo must contain an elm-package.json"
        end

        private

        def fetch_files
          fetched_files = []

          fetched_files << elm_package
          # Note: We *do not* fetch the exact-dependencies.json file, as it is
          # recommended that this is not committed

          fetched_files
        end

        def elm_package
          fetch_file_from_host("elm-package.json")
        end
      end
    end
  end
end
