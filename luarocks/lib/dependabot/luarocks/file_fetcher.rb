# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

module Dependabot
  module LuaRocks
    class FileFetcher < Dependabot::FileFetchers::Base
      ROCKSPEC_REGEXP = /rockspec/i

      def self.required_files_in?(filenames)
        filenames.any? { |f| f.match?(ROCKSPEC_REGEXP) }
      end

      def self.required_files_message
        "Repo must contain a rockspec."
      end

      private

      def fetch_files
        fetched_files = []
        fetched_files += rockspecs

        return fetched_files if fetched_files.any?

        raise(
            Dependabot::DependencyFileNotFound,
            File.join(directory, "<anything>.rockspec"),
            "No rockspecs found in #{directory}"
          )
      end

      def rockspecs
        @rockspecs ||=
          repo_contents(raise_errors: false).
          select { |f| f.type == "file" && f.name.match?(ROCKSPEC_REGEXP) }.
          map { |f| fetch_file_from_host(f.name) }
      end
    end
  end
end

Dependabot::FileFetchers.
  register("luarocks", Dependabot::LuaRocks::FileFetcher)
