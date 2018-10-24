# frozen_string_literal: true

require "dependabot/file_fetchers/base"

module Dependabot
  module FileFetchers
    module Go
      class Modules < Dependabot::FileFetchers::Base
        def self.required_files_in?(filenames)
          filenames.include?("go.mod")
        end

        def self.required_files_message
          "Repo must contain a go.mod."
        end

        private

        def fetch_files
          unless go_mod
            raise(
              Dependabot::DependencyFileNotFound,
              File.join(directory, "go.mod")
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

            return @main = file.tap { |f| f.support_file = true }
          end

          nil
        end
      end
    end
  end
end
