# frozen_string_literal: true

require "dependabot/file_fetchers/base"

module Dependabot
  module FileFetchers
    module Docker
      class Docker < Dependabot::FileFetchers::Base
        def self.required_files_in?(filenames)
          filenames.any? { |f| f.match?(/dockerfile/i) }
        end

        def self.required_files_message
          "Repo must contain a Dockerfile."
        end

        private

        def fetch_files
          fetched_files = []
          fetched_files += dockerfiles

          return fetched_files if fetched_files.any?

          raise(
            Dependabot::DependencyFileNotFound,
            File.join(directory, "Dockerfile")
          )
        end

        def dockerfiles
          @dockerfiles ||=
            repo_contents(raise_errors: false).
            select { |f| f.type == "file" && f.name.match?(/dockerfile/i) }.
            map { |f| fetch_file_from_host(f.name) }
        end
      end
    end
  end
end
