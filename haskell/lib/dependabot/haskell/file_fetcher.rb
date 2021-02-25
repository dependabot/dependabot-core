# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

module Dependabot
  module Haskell
    class FileFetcher < Dependabot::FileFetchers::Base
      def self.required_files_in?(filenames)
        filenames.any? { |f| f.end_with?(".cabal") }
      end

      def self.required_files_message
        "Repo must contain a .cabal file"
      end

      private

      def fetch_files
        fetched_files = []
        fetched_files += correctly_encoded_cabal_files

        return fetched_files if fetched_files.any?

        if incorrectly_encoded_cabal_files.none?
          raise(
            Dependabot::DependencyFileNotFound,
            File.join(directory, "**/*.cabal")
          )
        else
          raise(
            Dependabot::DependencyFileNotParseable,
            incorrectly_encoded_cabal_files.first.path
          )
        end
      end

      def cabal_files
        @cabal_files ||=
          repo_contents(raise_errors: false).
          select { |f| f.type == "file" && f.name.end_with?(".cabal") }.
          map { |f| fetch_file_from_host(f.name) }
      end

      def correctly_encoded_cabal_files
        cabal_files.select { |f| f.content.valid_encoding? }
      end

      def incorrectly_encoded_cabal_files
        cabal_files.reject { |f| f.content.valid_encoding? }
      end
    end
  end
end

Dependabot::FileFetchers.
  register("haskell", Dependabot::Haskell::FileFetcher)
