# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

module Dependabot
  module Hex
    class FileFetcher < Dependabot::FileFetchers::Base
      APPS_PATH_REGEX = /apps_path:\s*"(?<path>.*?)"/m.freeze
      STRING_ARG = %{(?:["'](.*?)["'])}
      EVAL_FILE = /Code\.eval_file\(#{STRING_ARG}(?:\s*,\s*#{STRING_ARG})?\)/.
                  freeze

      def self.required_files_in?(filenames)
        filenames.include?("mix.exs")
      end

      def self.required_files_message
        "Repo must contain a mix.exs."
      end

      private

      def fetch_files
        fetched_files = []
        fetched_files << mixfile
        fetched_files << lockfile if lockfile
        fetched_files += subapp_mixfiles
        fetched_files += evaled_files
        fetched_files
      end

      def mixfile
        @mixfile ||= fetch_file_from_host("mix.exs")
      end

      def lockfile
        return @lockfile if @lockfile_lookup_attempted

        @lockfile_lookup_attempted = true
        @lockfile ||= fetch_file_from_host("mix.lock")
      rescue Dependabot::DependencyFileNotFound
        nil
      end

      def subapp_mixfiles
        apps_path = mixfile.content.match(APPS_PATH_REGEX)&.
                    named_captures&.fetch("path")
        return [] unless apps_path

        app_directories = repo_contents(dir: apps_path).
                          select { |f| f.type == "dir" }

        app_directories.map do |dir|
          fetch_file_from_host("#{dir.path}/mix.exs")
        rescue Dependabot::DependencyFileNotFound
          # If the folder doesn't have a mix.exs it *might* be because it's
          # not an app. Ignore the fact we couldn't fetch one and proceed with
          # updating (it will blow up later if there are problems)
          nil
        end.compact
      rescue Octokit::NotFound, Gitlab::Error::NotFound
        # If the path specified in apps_path doesn't exist then it's not being
        # used. We can just return an empty array of subapp files.
        []
      end

      def evaled_files
        mixfile.content.scan(EVAL_FILE).map do |eval_file_args|
          path = Pathname.new(File.join(*eval_file_args.reverse)).
                 cleanpath.to_path
          fetch_file_from_host(path).tap { |f| f.support_file = true }
        end
      end
    end
  end
end

Dependabot::FileFetchers.register("hex", Dependabot::Hex::FileFetcher)
