# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

module Dependabot
  module GithubActions
    class FileFetcher < Dependabot::FileFetchers::Base
      FILENAME_PATTERN = /^(\.github|action.ya?ml)$/.freeze

      def self.required_files_in?(filenames)
        filenames.any? { |f| f.match?(FILENAME_PATTERN) }
      end

      def self.required_files_message
        "Repo must contain a .github/workflows directory with YAML files or an action.yml in the root"
      end

      private

      def fetch_files
        fetched_files = []
        fetched_files += correctly_encoded_workflow_files
        fetched_files += referenced_local_workflow_files

        return fetched_files if fetched_files.any?

        if incorrectly_encoded_workflow_files.none?
          raise(
            Dependabot::DependencyFileNotFound,
            File.join(directory, ".github/workflows/<anything>.yml")
          )
        else
          raise(
            Dependabot::DependencyFileNotParseable,
            incorrectly_encoded_workflow_files.first.path
          )
        end
      end

      def workflow_files
        @workflow_files ||=
          repo_contents(dir: ".github/workflows", raise_errors: false).
          select { |f| f.type == "file" && f.name.match?(/\.ya?ml$/) }.
          map { |f| fetch_file_from_host(".github/workflows/#{f.name}") } \
          + [fetch_file_if_present("action.yml"), fetch_file_if_present("action.yaml")].compact
      end

      def referenced_local_workflow_files
        # TODO: Fetch referenced local workflow files
        []
      end

      def correctly_encoded_workflow_files
        workflow_files.select { |f| f.content.valid_encoding? }
      end

      def incorrectly_encoded_workflow_files
        workflow_files.reject { |f| f.content.valid_encoding? }
      end
    end
  end
end

Dependabot::FileFetchers.
  register("github_actions", Dependabot::GithubActions::FileFetcher)
