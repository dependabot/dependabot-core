# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

module Dependabot
  module Docker
    class FileFetcher < Dependabot::FileFetchers::Base
      def self.required_files_in?(filenames)
        filenames.any? { |f| f.match?(/template|docker-image-version/i) }
      end

      def self.required_files_message
        "Repo must contain a pipeline yml."
      end

      private

      def fetch_files
        fetched_files = []
        fetched_files += correctly_encoded_template_file

        return fetched_files if fetched_files.any?

        if incorrectly_encoded_template_file.none?
          raise(
            Dependabot::DependencyFileNotFound,
            File.join(directory, "template")
          )
        else
          raise(
            Dependabot::DependencyFileNotParseable,
            incorrectly_encoded_template_file.first.path
          )
        end
      end

      def template_file
        @template_file ||=
          repo_contents(raise_errors: false).
          select { |f| f.type == "file" && f.name.match?(/template|docker-image-version/i) }.
          map { |f| fetch_file_from_host(f.name) }
      end

      def correctly_encoded_template_file
        template_file.select { |f| f.content.valid_encoding? }
      end

      def incorrectly_encoded_template_file
        template_file.reject { |f| f.content.valid_encoding? }
      end
    end
  end
end

Dependabot::FileFetchers.register("docker", Dependabot::Docker::FileFetcher)
