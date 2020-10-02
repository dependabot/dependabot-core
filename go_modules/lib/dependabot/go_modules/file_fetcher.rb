# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

module Dependabot
  module GoModules
    class FileFetcher < Dependabot::FileFetchers::Base
      def self.required_files_in?(filenames)
        filenames.include?("go.mod")
      end

      def self.required_files_message
        "Repo must contain a go.mod."
      end

      private

      def fetch_files
        # Ensure we always check out the full repo contents for go_module
        # updates.
        SharedHelpers.in_a_temporary_repo_directory(
          directory,
          clone_repo_contents
        ) do
          unless go_mod
            raise(
              Dependabot::DependencyFileNotFound,
              Pathname.new(File.join(directory, "go.mod")).
              cleanpath.to_path
            )
          end

          fetched_files = [go_mod]

          # Fetch the (optional) go.sum
          fetched_files << go_sum if go_sum

          # Fetch the main.go file if present, as this will later identify
          # this repo as an app.
          fetched_files << main if main

          fetched_files
        end
      end

      def go_mod
        @go_mod ||= fetch_file_if_present("go.mod")
      end

      def go_sum
        @go_sum ||= fetch_file_if_present("go.sum")
      end

      def main
        return @main if defined?(@main)

        go_files = Dir.glob("*.go")

        go_files.each do |filename|
          file_content = File.read(filename)
          next unless file_content.match?(/\s*package\s+main/)

          return @main = DependencyFile.new(
            name: Pathname.new(filename).cleanpath.to_path,
            directory: "/",
            type: "package_main",
            support_file: true,
            content: file_content
          )
        end

        nil
      end
    end
  end
end

Dependabot::FileFetchers.
  register("go_modules", Dependabot::GoModules::FileFetcher)
