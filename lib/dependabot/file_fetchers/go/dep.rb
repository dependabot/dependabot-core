# frozen_string_literal: true

require "dependabot/file_fetchers/base"

module Dependabot
  module FileFetchers
    module Go
      class Dep < Dependabot::FileFetchers::Base
        def self.required_files_in?(filenames)
          return true if (%w(Gopkg.toml Gopkg.lock) - filenames).empty?
          filenames.include?("go.mod")
        end

        def self.required_files_message
          "Repo must contain a Gopkg.toml and Gopkg.lock or a go.mod."
        end

        private

        # rubocop:disable Metrics/CyclomaticComplexity
        # rubocop:disable Metrics/PerceivedComplexity
        def fetch_files
          fetched_files = []
          fetched_files << manifest if manifest
          fetched_files << lockfile if lockfile
          fetched_files << go_mod if go_mod
          fetched_files << go_sum if go_sum

          if manifest && !lockfile
            raise(
              Dependabot::DependencyFileNotFound,
              File.join(directory, "Gopkg.lock")
            )
          end

          unless manifest || go_mod
            raise(
              Dependabot::DependencyFileNotFound,
              File.join(directory, "{go.mod,Gopkg.toml}")
            )
          end

          # Fetch the main.go file if present, as this will later identify
          # this repo as an app.
          fetched_files << main if main
          fetched_files
        end
        # rubocop:enable Metrics/CyclomaticComplexity
        # rubocop:enable Metrics/PerceivedComplexity

        def manifest
          @manifest ||= fetch_file_if_present("Gopkg.toml")
        end

        def lockfile
          @lockfile ||= fetch_file_if_present("Gopkg.lock")
        end

        def go_mod
          @go_mod ||= fetch_file_if_present("go.mod")
        end

        def go_sum
          @go_sum ||= fetch_file_if_present("go.sum")
        end

        def main
          return @main if @main

          go_files = repo_contents.select { |f| f.name.end_with?(".go") }

          go_files.each do |go_file|
            file = fetch_file_from_host(go_file.name, type: "package_main")
            next unless file.content.match?(/\s*package\s+main/)
            return @main = file
          end

          nil
        end
      end
    end
  end
end
