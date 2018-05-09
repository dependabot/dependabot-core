# frozen_string_literal: true

require "dependabot/file_fetchers/base"

module Dependabot
  module FileFetchers
    module Php
      class Composer < Dependabot::FileFetchers::Base
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
          fetched_files += path_dependencies
          fetched_files
        end

        def composer_json
          @composer_json ||= fetch_file_from_host("composer.json")
        end

        def composer_lock
          @composer_lock ||= fetch_file_from_host("composer.lock")
        rescue Dependabot::DependencyFileNotFound
          nil
        end

        def path_dependencies
          @path_dependencies ||=
            begin
              path_sources =
                JSON.parse(composer_json.content).
                fetch("repositories", []).
                select { |details| details["type"] == "path" }.
                map { |details| details["url"] }

              composer_json_files = []
              unfetchable_deps = []

              path_sources.each do |path|
                directories = path.end_with?("*") ? expand_path(path) : [path]

                directories.each do |directory|
                  file = File.join(directory, "composer.json")

                  begin
                    composer_json_files <<
                      fetch_file_from_host(file, type: "path_dependency")
                  rescue Dependabot::DependencyFileNotFound
                    # Collected, but currently ignored
                    unfetchable_deps << file
                  end
                end
              end

              composer_json_files
            end
        end

        def expand_path(path)
          repo_contents(dir: path.gsub(/\*$/, "")).
            select { |file| file.type == "dir" }.
            map { |f| path.gsub(/\*$/, f.name) }
        end
      end
    end
  end
end
