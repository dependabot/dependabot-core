# typed: strict
# frozen_string_literal: true

require_relative "../shared/base_file_fetcher"

module Dependabot
  module DockerCompose
    class FileFetcher < Dependabot::Shared::BaseFileFetcher
      FILENAME_REGEX = /(docker-)?compose(?>\.[\w-]+)?\.ya?ml/i

      sig { override.returns(Regexp) }
      def self.filename_regex
        FILENAME_REGEX
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
