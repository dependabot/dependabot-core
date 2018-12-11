# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

module Dependabot
  module Elm
    class FileFetcher < Dependabot::FileFetchers::Base
      def self.required_files_in?(filenames)
        return true if filenames.include?("elm-package.json")

        filenames.include?("elm.json")
      end

      def self.required_files_message
        "Repo must contain an elm-package.json or an elm.json"
      end

      private

      def fetch_files
        fetched_files = []

        fetched_files << elm_package if elm_package
        fetched_files << elm_json if elm_json

        # Note: We *do not* fetch the exact-dependencies.json file, as it is
        # recommended that this is not committed

        check_required_files_present
        fetched_files
      end

      def check_required_files_present
        return if elm_package || elm_json

        path = Pathname.new(File.join(directory, "elm.json")).
               cleanpath.to_path
        raise Dependabot::DependencyFileNotFound, path
      end

      def elm_package
        @elm_package ||= fetch_file_if_present("elm-package.json")
      end

      def elm_json
        @elm_json ||= fetch_file_if_present("elm.json")
      end
    end
  end
end

Dependabot::FileFetchers.register("elm_package", Dependabot::Elm::FileFetcher)
