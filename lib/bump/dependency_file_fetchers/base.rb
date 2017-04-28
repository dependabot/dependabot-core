# frozen_string_literal: true
require "bump/dependency_file"
require "bump/errors"

module Bump
  module DependencyFileFetchers
    class Base
      attr_reader :repo, :github_client

      def initialize(repo:, github_client:)
        @repo = repo
        @github_client = github_client
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
        content = github_client.contents(repo.name, path: file_name).content
        DependencyFile.new(name: file_name, content: Base64.decode64(content))
      rescue Octokit::NotFound
        raise Bump::DependencyFileNotFound
      end
    end
  end
end
