# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

module Dependabot
  module DockerCompose
    class FileFetcher < Dependabot::FileFetchers::Base
      FILENAME_REGEX = /docker-compose(?>\.override)?\.yml/i.freeze

      def self.required_files_in?(filenames)
        filenames.any? { |f| f.match?(FILENAME_REGEX) }
      end

      def self.required_files_message
        "Repo must contain a docker-compose.yaml file."
      end

      private

      def fetch_files
        fetched_files = []
        fetched_files += correctly_encoded_docker_compose_files

        return fetched_files if fetched_files.any?

        if incorrectly_encoded_docker_compose_files.none?
          raise(
            Dependabot::DependencyFileNotFound,
            File.join(directory, "docker-compose.yml")
          )
        else
          raise(
            Dependabot::DependencyFileNotParseable,
            incorrectly_encoded_docker_compose_files.first.path
          )
        end
      end

      def docker_compose_files
        @docker_compose_files ||=
          repo_contents(raise_errors: false).
          select { |f| f.type == "file" && f.name.match?(FILENAME_REGEX) }.
          map { |f| fetch_file_from_host(f.name) }
      end

      def correctly_encoded_docker_compose_files
        docker_compose_files.select { |f| f.content.valid_encoding? }
      end

      def incorrectly_encoded_docker_compose_files
        docker_compose_files.reject { |f| f.content.valid_encoding? }
      end
    end
  end
end

Dependabot::FileFetchers.register(
  "docker_compose",
  Dependabot::DockerCompose::FileFetcher
)
