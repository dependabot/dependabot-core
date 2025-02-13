# typed: strict
# frozen_string_literal: true

require "dependabot/shared/shared_file_fetcher"

module Dependabot
  module DockerCompose
    class FileFetcher < Dependabot::Shared::SharedFileFetcher
      FILENAME_REGEX = /(docker-)?compose(?>\.[\w-]+)?\.ya?ml/i

      sig { override.returns(T::Array[DependencyFile]) }
      def fetch_files
        fetched_files = correctly_encoded_docker_compose_files

        return fetched_files if fetched_files.any?

        raise_appropriate_error
      end

      sig { override.returns(Regexp) }
      def self.filename_regex
        FILENAME_REGEX
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

      sig { override.returns(String) }
      def self.required_files_message
        "Repo must contain a docker-compose.yaml file."
      end

      private

      sig { override.returns(String) }
      def default_file_name
        "docker-compose.yml"
      end

      sig { override.returns(String) }
      def file_type
        "Docker Compose"
      end
    end
  end
end

Dependabot::FileFetchers.register(
  "docker_compose",
  Dependabot::DockerCompose::FileFetcher
)
