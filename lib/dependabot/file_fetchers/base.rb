# frozen_string_literal: true

require "dependabot/dependency_file"
require "dependabot/errors"
require "octokit"

module Dependabot
  module FileFetchers
    class Base
      attr_reader :repo, :github_client, :directory

      def self.required_files_in?(_)
        raise NotImplementedError
      end

      def self.required_files_message
        raise NotImplementedError
      end

      def initialize(repo:, github_client:, directory: "/")
        @repo = repo
        @github_client = github_client
        @directory = directory
      end

      def files
        @files ||= fetch_files
      end

      def commit
        @commit ||=
          begin
            default_branch = github_client.repository(repo).default_branch
            github_client.ref(repo, "heads/#{default_branch}").object.sha
          end
      end

      private

      def fetch_file_from_github(file_name)
        path = Pathname.new(File.join(directory, file_name)).cleanpath.to_path
        content = github_client.contents(repo, path: path, ref: commit).content

        DependencyFile.new(
          name: Pathname.new(file_name).cleanpath.to_path,
          content: Base64.decode64(content).force_encoding("UTF-8").encode,
          directory: directory,
          repo: repo
        )
      rescue Octokit::NotFound
        raise Dependabot::DependencyFileNotFound, path
      end
    end
  end
end
