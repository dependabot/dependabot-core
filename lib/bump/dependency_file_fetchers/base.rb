# frozen_string_literal: true
require "bump/dependency_file"
require "bump/github"

module Bump
  module DependencyFileFetchers
    class Base
      attr_reader :repo

      def initialize(repo)
        @repo = repo
      end

      def files
        raise NotImplementedError
      end

      def commit
        default_branch = Github.client.repository(repo).default_branch

        Github.client.ref(repo, "heads/#{default_branch}").object.sha
      end

      private

      def fetch_file_from_github(name)
        content = Github.client.contents(repo, path: name).content

        DependencyFile.new(name: name, content: Base64.decode64(content))
      end
    end
  end
end
