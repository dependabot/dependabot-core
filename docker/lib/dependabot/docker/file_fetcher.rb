# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

module Dependabot
  module Docker
    class FileFetcher < Dependabot::FileFetchers::Base
      PATH_REGEX = /dockerfile|template|docker-image-version/i.freeze
      def self.required_files_in?(filenames)
        filenames.any? { |f| f.match?(PATH_REGEX) }
      end

      def self.required_files_message
        "Repo must contain a Dockerfile or a Concourse pipeline file."
      end

      private

      def fetch_files
        fetched_files = []
        fetched_files += correctly_encoded_file

        return fetched_files if fetched_files.any?

        if incorrectly_encoded_file.none?
          raise(
            Dependabot::DependencyFileNotFound,
            "No Dockerfile or Concourse pipeline file \
            found at path: #{directory}."
          )
        else
          raise(
            Dependabot::DependencyFileNotParseable,
            incorrectly_encoded_file.first.path
          )
        end
      end

      def fetched_file
        @fetched_file ||=
          repo_contents(raise_errors: false).
          select { |f| f.type == "file" && f.name.match?(PATH_REGEX) }.
          map { |f| fetch_file_from_host(f.name) }
      end

      def correctly_encoded_file
        fetched_file.select { |f| f.content.valid_encoding? }
      end

      def incorrectly_encoded_file
        fetched_file.reject { |f| f.content.valid_encoding? }
      end
    end
  end
end

Dependabot::FileFetchers.register("docker", Dependabot::Docker::FileFetcher)
