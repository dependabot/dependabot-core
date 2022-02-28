# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

module Dependabot
  module Cake
    class FileFetcher < Dependabot::FileFetchers::Base
      require_relative "file_fetcher/script_paths_finder"
      require_relative "file_fetcher/wildcard_search"

      def initialize(source:, credentials:, repo_contents_path: nil)
        super(source: source, credentials: credentials,
              repo_contents_path: repo_contents_path)
        @wildcard_search = WildcardSearch.new(
          enumerate_files_fn:
              ->(dir) { repo_contents(dir: dir) }
        )
      end

      def self.required_files_in?(filenames)
        filenames.any? { |f| f.end_with?(".cake") }
      end

      def self.required_files_message
        "Repo must contain a .cake file."
      end

      private

      attr_reader :wildcard_search

      def fetch_files
        fetched_files = []
        fetched_files += correctly_encoded_cake_files

        if fetched_files.any?
          fetched_files += imported_script_files(fetched_files)
          fetched_files << cake_config_file if cake_config_file
          fetched_files += nuget_config_files
          fetched_files = fetched_files.uniq
          return fetched_files
        end

        if incorrectly_encoded_cake_files.none?
          raise(
            Dependabot::DependencyFileNotFound,
            File.join(directory, "<anything>.cake")
          )
        else
          raise(
            Dependabot::DependencyFileNotParseable,
            incorrectly_encoded_cake_files.first.path
          )
        end
      end

      def cake_files
        @cake_files ||=
          repo_contents(raise_errors: false).
          select { |f| f.type == "file" && f.name.end_with?(".cake") }.
          map { |f| fetch_file_from_host(f.name) }
      end

      def correctly_encoded_cake_files
        cake_files.select { |f| f.content.valid_encoding? }
      end

      def incorrectly_encoded_cake_files
        cake_files.reject { |f| f.content.valid_encoding? }
      end

      def cake_config_file
        @cake_config_file ||= fetch_file_if_present("cake.config")&.
          tap { |f| f.support_file = true }
      end

      def nuget_config_files
        return @nuget_config_files if @nuget_config_files

        candidate_paths = ["."]

        @nuget_config_files ||=
          candidate_paths.map do |dir|
            file = repo_contents(dir: dir).
                   find { |f| f.name.casecmp("nuget.config").zero? }
            file = fetch_file_from_host(File.join(dir, file.name)) if file
            file&.tap { |f| f.support_file = true }
          end.compact
      end

      def imported_script_files(cake_files)
        imported_script_files = []

        cake_files.each do |cake_file|
          previously_fetched_files = cake_files + imported_script_files
          imported_script_files +=
            fetch_imported_script_files(
              file: cake_file,
              previously_fetched_files: previously_fetched_files
            )
        end

        imported_script_files
      end

      def fetch_imported_script_files(file:, previously_fetched_files:)
        paths = ScriptPathsFinder.new(cake_file: file).import_paths(
          base_path: directory,
          wildcard_search: @wildcard_search
        )

        paths.flat_map do |path|
          next if previously_fetched_files.map(&:name).include?(path)
          next if file.name == path

          fetched_file = fetch_file_from_host(path)
          grandchild_script_files = fetch_imported_script_files(
            file: fetched_file,
            previously_fetched_files: previously_fetched_files + [file]
          )
          [fetched_file, *grandchild_script_files]
        rescue Dependabot::DependencyFileNotFound
          # Don't worry about missing files too much
          nil
        end.compact
      end
    end
  end
end

Dependabot::FileFetchers.register("cake", Dependabot::Cake::FileFetcher)
