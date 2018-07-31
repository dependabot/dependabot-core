# frozen_string_literal: true

require "dependabot/file_fetchers/base"

module Dependabot
  module FileFetchers
    module Elixir
      class Hex < Dependabot::FileFetchers::Base
        APPS_PATH_REGEX = /apps_path:\s*"(?<path>.*?)"/m
        def self.required_files_in?(filenames)
          (%w(mix.exs mix.lock) - filenames).empty?
        end

        def self.required_files_message
          "Repo must contain a mix.exs and a mix.lock."
        end

        private

        def fetch_files
          fetched_files = []
          fetched_files << mixfile
          fetched_files << lockfile
          fetched_files += subapp_mixfiles
          fetched_files
        end

        def mixfile
          @mixfile ||= fetch_file_from_host("mix.exs")
        end

        def lockfile
          @lockfile ||= fetch_file_from_host("mix.lock")
        end

        def subapp_mixfiles
          apps_path = mixfile.content.match(APPS_PATH_REGEX)&.
                      named_captures.fetch("path")
          return [] unless apps_path

          app_directories = repo_contents(dir: apps_path).
                            select { |f| f.type == "dir" }

          app_directories.map do |dir|
            fetch_file_from_host("#{dir.path}/mix.exs")
          rescue Dependabot::DependencyFileNotFound
            # If the folder doesn't have a mix.exs is *might* be because it's
            # not an app. Ignore the fact we couldn't fetch one and proceed with
            # updating (it will blow up later if there are problems)
            nil
          end.compact
        end
      end
    end
  end
end
