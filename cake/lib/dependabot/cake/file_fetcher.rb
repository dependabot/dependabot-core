# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

module Dependabot
  module Cake
    class FileFetcher < Dependabot::FileFetchers::Base
      def self.required_files_in?(filenames)
        filenames.any? { |f| f.end_with?(".cake") }
      end

      def self.required_files_message
        "Repo must contain a Cake file."
      end

      private

      def fetch_files
        fetched_files = []
        fetched_files += cakefiles

        return fetched_files if fetched_files.any?

        raise(
          Dependabot::DependencyFileNotFound,
          File.join(directory, "<anything>.cake")
        )
      end

      def cakefiles
        @cakefiles ||=
          repo_contents(raise_errors: false).
          select { |f| f.type == "file" && f.name.end_with?(".cake") }.
          map { |f| fetch_file_from_host(f.name) }
      end
    end
  end
end

Dependabot::FileFetchers.register("cake", Dependabot::Cake::FileFetcher)
