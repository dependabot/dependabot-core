# frozen_string_literal: true

require "json"
require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

module Dependabot
  module Composer
    class FileFetcher < Dependabot::FileFetchers::Base
      require_relative "file_fetcher/path_dependency_builder"

      def self.required_files_in?(filenames)
        filenames.include?("composer.json")
      end

      def self.required_files_message
        "Repo must contain a composer.json."
      end

      private

      def fetch_files
        fetched_files = []
        fetched_files << composer_json
        fetched_files << composer_lock if composer_lock
        fetched_files << auth_json if auth_json
        fetched_files += path_dependencies
        fetched_files
      end

      def composer_json
        @composer_json ||= fetch_file_from_host("composer.json")
      end

      def composer_lock
        return @composer_lock if @composer_lock_lookup_attempted

        @composer_lock_lookup_attempted = true
        @composer_lock ||= fetch_file_if_present("composer.lock")
      end

      # NOTE: This is fetched but currently unused
      def auth_json
        @auth_json ||= fetch_file_if_present("auth.json")&.
                       tap { |f| f.support_file = true }
      end

      def path_dependencies
        @path_dependencies ||=
          begin
            composer_json_files = []
            unfetchable_deps = []

            path_sources.each do |path|
              directories = path.end_with?("*") ? expand_path(path) : [path]

              directories.each do |dir|
                file = File.join(dir, "composer.json")

                begin
                  composer_json_files << fetch_file_with_root_fallback(file)
                rescue Dependabot::DependencyFileNotFound
                  unfetchable_deps << dir
                end
              end
            end

            composer_json_files += build_unfetchable_deps(unfetchable_deps)

            # Mark the path dependencies as support files - we don't currently
            # parse or update them.
            composer_json_files.tap do |files|
              files.each { |f| f.support_file = true }
            end
          end
      end

      def path_sources
        @path_sources ||=
          begin
            repos = parsed_composer_json.fetch("repositories", [])
            if repos.is_a?(Hash) || repos.is_a?(Array)
              repos = repos.values if repos.is_a?(Hash)
              repos = repos.select { |r| r.is_a?(Hash) }

              repos.
                select { |details| details["type"] == "path" }.
                map { |details| details["url"] }
            else
              []
            end
          end
      end

      def build_unfetchable_deps(unfetchable_deps)
        unfetchable_deps.filter_map do |path|
          PathDependencyBuilder.new(
            path: path,
            directory: directory,
            lockfile: composer_lock
          ).dependency_file
        end
      end

      def expand_path(path)
        wildcard_depth = 0
        path = path.gsub(/\*$/, "")
        while path.end_with?("*/")
          path = path.gsub(%r{\*/$}, "")
          wildcard_depth += 1
        end
        directories = repo_contents(dir: path).
                      select { |file| file.type == "dir" }.
                      map { |f| File.join(path, f.name) }

        while wildcard_depth.positive?
          directories.each do |dir|
            directories += repo_contents(dir: dir).
                           select { |file| file.type == "dir" }.
                           map { |f| File.join(dir, f.name) }
          end
          wildcard_depth -= 1
        end
        directories
      rescue Octokit::NotFound, Gitlab::Error::NotFound
        lockfile_path_dependency_paths.
          select { |p| p.to_s.start_with?(path.gsub(/\*$/, "")) }
      end

      def lockfile_path_dependency_paths
        keys = FileParser::DEPENDENCY_GROUP_KEYS.
               map { |h| h.fetch(:lockfile) }

        keys.flat_map do |key|
          next [] unless parsed_lockfile[key]

          parsed_lockfile[key].
            select { |details| details.dig("dist", "type") == "path" }.
            map { |details| details.dig("dist", "url") }
        end
      end

      def parsed_composer_json
        @parsed_composer_json ||= JSON.parse(composer_json.content)
      rescue JSON::ParserError
        raise Dependabot::DependencyFileNotParseable, composer_json.path
      end

      def parsed_lockfile
        return {} unless composer_lock

        @parsed_lockfile ||= JSON.parse(composer_lock.content)
      rescue JSON::ParserError
        {}
      end

      def fetch_file_with_root_fallback(filename)
        path = Pathname.new(File.join(directory, filename)).cleanpath.to_path

        begin
          fetch_file_from_host(filename, fetch_submodules: true)
        rescue Dependabot::DependencyFileNotFound
          # If the file isn't found at the full path, try looking for it
          # without considering the directory (i.e., check if the path should
          # have been relative to the root of the repository).
          cleaned_filename = filename.gsub(/^\./, "")
          cleaned_filename = Pathname.new(cleaned_filename).cleanpath.to_path

          DependencyFile.new(
            name: Pathname.new(filename).cleanpath.to_path,
            content: _fetch_file_content(cleaned_filename),
            directory: directory,
            type: "file"
          )
        end
      rescue Octokit::NotFound, Gitlab::Error::NotFound
        raise Dependabot::DependencyFileNotFound, path
      end
    end
  end
end

Dependabot::FileFetchers.register("composer", Dependabot::Composer::FileFetcher)
