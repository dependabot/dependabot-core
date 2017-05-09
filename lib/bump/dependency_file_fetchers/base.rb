# frozen_string_literal: true
require "bump/dependency_file"
require "bump/errors"

module Bump
  module DependencyFileFetchers
    class Base
      attr_reader :repo, :github_client, :directory

      def initialize(repo:, github_client:, directory: "/")
        @repo = repo
        @github_client = github_client
        @directory = directory
      end

      def files
        raise NotImplementedError
      end

      def commit
        default_branch = github_client.repository(repo.name).default_branch
        github_client.ref(repo.name, "heads/#{default_branch}").object.sha
      end

      private

      def fetch_file_from_github(file_name)
        file_path = File.join(directory, file_name)
        content = github_client.contents(repo.name, path: file_path).content

        DependencyFile.new(
          name: file_name,
          content: Base64.decode64(content),
          directory: directory
        )
      rescue Octokit::NotFound
        raise Bump::DependencyFileNotFound, file_path
      end
    end
  end
end
