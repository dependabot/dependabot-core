# typed: strict
# frozen_string_literal: true

require "dependabot/shared/shared_file_fetcher"

module Dependabot
  module Helm
    class FileFetcher < Dependabot::Shared::SharedFileFetcher
      FILENAME_REGEX = /.*\.ya?ml$/i
      CHART_LOCK_REGEXP = /Chart\.lock/i

      sig { override.returns(T::Array[DependencyFile]) }
      def fetch_files
        fetched_files = []
        fetched_files += correctly_encoded_helm_files
        fetched_files += chart_locks

        return fetched_files if fetched_files.any?

        raise_appropriate_error
      end

      sig { override.returns(Regexp) }
      def self.filename_regex
        FILENAME_REGEX
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def helm_files
        @helm_files ||=
          T.let(repo_contents(raise_errors: false)
          .select { |f| f.type == "file" && f.name.match?(FILENAME_REGEX) }
          .map { |f| fetch_file_from_host(f.name) }, T.nilable(T::Array[DependencyFile]))
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def chart_locks
        @chart_locks ||=
          T.let(repo_contents(raise_errors: false)
          .select { |f| f.type == "file" && f.name.match?(CHART_LOCK_REGEXP) }
          .map { |f| fetch_file_from_host(f.name) }, T.nilable(T::Array[DependencyFile]))
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def correctly_encoded_helm_files
        helm_files.select { |f| T.must(f.content).valid_encoding? }
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def incorrectly_encoded_helm_files_files
        helm_files.reject { |f| T.must(f.content).valid_encoding? }
      end

      sig { override.returns(String) }
      def self.required_files_message
        "Repo must contain a Helm charts file."
      end

      private

      sig { override.returns(String) }
      def default_file_name
        "Chart.yaml"
      end

      sig { override.returns(String) }
      def file_type
        "Helm Chart"
      end
    end
  end
end

Dependabot::FileFetchers.register(
  "helm",
  Dependabot::Helm::FileFetcher
)
