# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

module Dependabot
  module Elm
    class FileFetcher < Dependabot::FileFetchers::Base
      def self.required_files_in?(filenames)
        filenames.include?("elm.json")
      end

      def self.required_files_message(_directory = "/")
        "Repo must contain an elm-package.json or an elm.json"
      end

      private

      def fetch_files
        fetched_files = []

        fetched_files << elm_json if elm_json

        # NOTE: We *do not* fetch the exact-dependencies.json file, as it is
        # recommended that this is not committed

        fetched_files
      end

      def elm_json
        return @elm_json if defined?(@elm_json)

        @elm_json = fetch_file_if_present("elm.json")
      end
    end
  end
end

Dependabot::FileFetchers.register("elm", Dependabot::Elm::FileFetcher)
