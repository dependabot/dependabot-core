# frozen_string_literal: true

require "dependabot/file_fetchers/base"

module Dependabot
  module FileFetchers
    module Elm
      class ElmPackage < Dependabot::FileFetchers::Base
        def self.required_files_in?(filenames)
          (required_files - filenames).empty?
        end

        def self.required_files_message
          "Repo must contain an " + required_files.join(" and an ")
        end

        private

        def fetch_files
          # Note: We *do not* fetch the exact-dependencies.json file, as it is
          # recommended that this is not committed
          required_files.map { |filename| fetch_file_from_host(filename) }
        end

        def required_files
          ["elm-package.json"]
        end
      end
    end
  end
end
