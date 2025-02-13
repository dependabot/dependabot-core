# typed: strict
# frozen_string_literal: true

require "dependabot/shared/utils/helpers"
require "dependabot/shared/shared_file_fetcher"

module Dependabot
  module Docker
    class FileFetcher < Dependabot::Shared::SharedFileFetcher
      extend T::Sig

      DOCKER_REGEXP = /dockerfile|containerfile/i

      sig { override.returns(Regexp) }
      def self.filename_regex
        DOCKER_REGEXP
      end

      sig { override.returns(String) }
      def self.required_files_message
        "Repo must contain a Dockerfile, Containerfile, or Kubernetes YAML files."
      end

      private

      sig { override.returns(String) }
      def default_file_name
        "Dockerfile"
      end

      sig { override.returns(String) }
      def file_type
        "Docker"
      end

      sig { override.returns(T::Array[DependencyFile]) }
      def fetch_files
        fetched_files = correctly_encoded_dockerfiles
        fetched_files += super

        return fetched_files if fetched_files.any?

        raise_appropriate_error(incorrectly_encoded_dockerfiles)
      end

      sig { override.params(filenames: T::Array[String]).returns(T::Boolean) }
      def self.required_files_in?(filenames)
        filenames.any? { |f| f.match?(DOCKER_REGEXP) } or
          filenames.any? { |f| f.match?(YAML_REGEXP) }
      end

      sig { returns(T::Array[DependencyFile]) }
      def dockerfiles
        @dockerfiles ||= T.let(fetch_candidate_dockerfiles, T.nilable(T::Array[DependencyFile]))
      end

      sig { returns(T::Array[DependencyFile]) }
      def fetch_candidate_dockerfiles
        repo_contents(raise_errors: false)
          .select { |f| f.type == "file" && f.name.match?(self.class.filename_regex) }
          .map { |f| fetch_file_from_host(f.name) }
      end

      sig { returns(T::Array[DependencyFile]) }
      def correctly_encoded_dockerfiles
        dockerfiles.select { |f| f.content&.valid_encoding? }
      end

      sig { returns(T::Array[DependencyFile]) }
      def incorrectly_encoded_dockerfiles
        dockerfiles.reject { |f| f.content&.valid_encoding? }
      end
    end
  end
end

Dependabot::FileFetchers.register("docker", Dependabot::Docker::FileFetcher)
