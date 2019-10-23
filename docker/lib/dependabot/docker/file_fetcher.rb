# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

module Dependabot
  module Docker
    class FileFetcher < Dependabot::FileFetchers::Base
      def self.required_files_in?(filenames)
        filenames.any? { |f| f.match?(/dockerfile|.drone.yml/i) }
      end

      def self.required_files_message
        "Repo must contain a Dockerfile and/or a .drone.yml"
      end

      private

      def fetch_files
        fetched_files = []
        fetched_files += correctly_encoded_dockerfiles
        fetched_files += drone_files

        return fetched_files if fetched_files.any?

        if incorrectly_encoded_dockerfiles.none?
          raise(
            Dependabot::DependencyFileNotFound,
            File.join(directory, "Dockerfile")
          )
        else
          raise(
            Dependabot::DependencyFileNotParseable,
            incorrectly_encoded_dockerfiles.first.path
          )
        end
      end

      def dockerfiles
        @dockerfiles ||=
          repo_contents(raise_errors: false).
          select { |f| f.type == "file" && f.name.match?(/dockerfile/i) }.
          map { |f| fetch_file_from_host(f.name) }
      end

      def correctly_encoded_dockerfiles
        dockerfiles.select { |f| f.content.valid_encoding? }
      end

      def incorrectly_encoded_dockerfiles
        dockerfiles.reject { |f| f.content.valid_encoding? }
      end

      def drone_files
        @drone_files ||=
          repo_contents(raise_errors: false).
          select { |f| f.type == "file" && f.name.match?(/.drone.yml/i) }.
          map { |f| fetch_file_from_host(f.name) }
      end
    end
  end
end

Dependabot::FileFetchers.register("docker", Dependabot::Docker::FileFetcher)
