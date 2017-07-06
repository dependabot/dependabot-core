# frozen_string_literal: true
require "dependabot/dependency_file"
require "dependabot/errors"
require "octokit"

module Dependabot
  module FileFetchers
    class Base
      attr_reader :repo, :github_client, :directory

      def self.required_files
        raise NotImplementedError
      end

      def initialize(repo:, github_client:, directory: "/")
        @repo = repo
        @github_client = github_client
        @directory = directory
      end

      def files
        @files ||= required_files + extra_files
      end

      def commit
        @commit ||=
          begin
            default_branch = github_client.repository(repo).default_branch
            github_client.ref(repo, "heads/#{default_branch}").object.sha
          end
      end

      private

      def required_files
        @required_files ||= self.class.required_files.map do |name|
          fetch_file_from_github(name)
        end
      end

      def extra_files
        []
      end

      def fetch_file_from_github(file_name)
        file_path = File.join(directory, file_name)
        file_path = Pathname.new(file_path).cleanpath.to_path
        content =
          github_client.contents(repo, path: file_path, ref: commit).content

        DependencyFile.new(
          name: file_name,
          content: Base64.decode64(content).force_encoding("UTF-8").encode,
          directory: directory
        )
      rescue Octokit::NotFound
        raise Dependabot::DependencyFileNotFound, file_path
      end
    end
  end
end
