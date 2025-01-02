# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"
require "dependabot/github_actions/constants"

module Dependabot
  module GithubActions
    class FileFetcher < Dependabot::FileFetchers::Base
      extend T::Sig
      extend T::Helpers

      sig { override.params(filenames: T::Array[String]).returns(T::Boolean) }
      def self.required_files_in?(filenames)
        filenames.any? { |f| f.match?(MANIFEST_FILE_PATTERN) }
      end

      sig { override.returns(String) }
      def self.required_files_message
        "Repo must contain a #{WORKFLOW_DIRECTORY} directory with YAML files or " \
          "an #{MANIFEST_FILE_YML} file"
      end

      sig do
        override
          .params(
            source: Dependabot::Source,
            credentials: T::Array[Dependabot::Credential],
            repo_contents_path: T.nilable(String),
            options: T::Hash[String, String]
          )
          .void
      end
      def initialize(source:, credentials:, repo_contents_path: nil, options: {})
        @workflow_files = T.let([], T::Array[DependencyFile])
        super
      end

      sig { override.returns(T::Array[DependencyFile]) }
      def fetch_files
        fetched_files = []
        fetched_files += correctly_encoded_workflow_files

        return fetched_files if fetched_files.any?

        if incorrectly_encoded_workflow_files.none?
          expected_paths =
            if directory == "/"
              File.join(directory, MANIFEST_FILE_YML) + " or /#{CONFIG_YMLS}"
            else
              File.join(directory, ANYTHING_YML)
            end

          raise(
            Dependabot::DependencyFileNotFound,
            expected_paths
          )
        else
          raise(
            Dependabot::DependencyFileNotParseable,
            T.must(incorrectly_encoded_workflow_files.first).path
          )
        end
      end

      private

      sig { returns(T::Array[DependencyFile]) }
      def workflow_files
        return @workflow_files unless @workflow_files.empty?

        # In the special case where the root directory is defined we also scan
        # the .github/workflows/ folder.
        if directory == "/"
          @workflow_files += [
            fetch_file_if_present(MANIFEST_FILE_YML),
            fetch_file_if_present(MANIFEST_FILE_YAML)
          ].compact

          workflows_dir = WORKFLOW_DIRECTORY
        else
          workflows_dir = "."
        end

        @workflow_files +=
          repo_contents(dir: workflows_dir, raise_errors: false)
          .select { |f| f.type == "file" && f.name.match?(MANIFEST_FILE_PATTERN) }
          .map { |f| fetch_file_from_host("#{workflows_dir}/#{f.name}") }
      end

      sig { returns(T::Array[DependencyFile]) }
      def correctly_encoded_workflow_files
        workflow_files.select { |f| f.content&.valid_encoding? }
      end

      sig { returns(T::Array[DependencyFile]) }
      def incorrectly_encoded_workflow_files
        workflow_files.reject { |f| f.content&.valid_encoding? }
      end
    end
  end
end

Dependabot::FileFetchers
  .register("github_actions", Dependabot::GithubActions::FileFetcher)
