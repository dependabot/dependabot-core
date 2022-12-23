# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

module Dependabot
  module GithubActions
    class FileFetcher < Dependabot::FileFetchers::Base
      FILENAME_PATTERN = /^(\.github|action.ya?ml)$/

      def self.required_files_in?(filenames)
        filenames.any? { |f| f.match?(FILENAME_PATTERN) }
      end

      def self.required_files_message
        "Repo must contain a .github/workflows directory with YAML files or an action.yml file"
      end

      private

      def fetch_files
        fetched_files = []
        fetched_files += correctly_encoded_workflow_files
        fetched_files += referenced_local_workflow_files

        return fetched_files if fetched_files.any?

        if incorrectly_encoded_workflow_files.none?
          expected_paths =
            if directory == "/"
              File.join(directory, "action.yml") + " or /.github/workflows/<anything>.yml"
            else
              File.join(directory, "<anything>.yml")
            end

          raise(
            Dependabot::DependencyFileNotFound,
            expected_paths
          )
        else
          raise(
            Dependabot::DependencyFileNotParseable,
            incorrectly_encoded_workflow_files.first.path
          )
        end
      end

      def workflow_files
        return @workflow_files if defined? @workflow_files

        @workflow_files = []

        # In the special case where the root directory is defined we also scan
        # the .github/workflows/ folder.
        if directory == "/"
          @workflow_files += [fetch_file_if_present("action.yml"), fetch_file_if_present("action.yaml")].compact

          workflows_dir = ".github/workflows"
        else
          workflows_dir = "."
        end

        @workflow_files +=
          repo_contents(dir: workflows_dir, raise_errors: false).
          select { |f| f.type == "file" && f.name.match?(/\.ya?ml$/) }.
          map { |f| fetch_file_from_host("#{workflows_dir}/#{f.name}") }
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
