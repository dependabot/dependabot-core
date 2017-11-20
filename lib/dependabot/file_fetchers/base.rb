# frozen_string_literal: true

require "dependabot/dependency_file"
require "dependabot/errors"
require "octokit"

module Dependabot
  module FileFetchers
    class Base
      attr_reader :source, :credentials, :directory, :target_branch

      def self.required_files_in?(_)
        raise NotImplementedError
      end

      def self.required_files_message
        raise NotImplementedError
      end

      def initialize(source:, credentials:, directory: "/", target_branch: nil)
        @source = source
        @credentials = credentials
        @directory = directory
        @target_branch = target_branch
      end

      def repo
        source.fetch(:repo)
      end

      def host
        source.fetch(:host)
      end

      def files
        @files ||= fetch_files
      end

      def commit
        @commit ||=
          begin
            branch = target_branch ||
                     github_client.repository(repo).default_branch
            github_client.ref(repo, "heads/#{branch}").object.sha
          end
      end

      private

      def fetch_file_from_github(file_name)
        path = Pathname.new(File.join(directory, file_name)).cleanpath.to_path
        content = github_client.contents(repo, path: path, ref: commit).content

        DependencyFile.new(
          name: Pathname.new(file_name).cleanpath.to_path,
          content: Base64.decode64(content).force_encoding("UTF-8").encode,
          directory: directory
        )
      rescue Octokit::NotFound
        raise Dependabot::DependencyFileNotFound, path
      end

      # One day day this class, and all others, will be provider agnostic. For
      # now it's fine that it only supports GitHub.
      def github_client
        access_token =
          credentials.
          find { |cred| cred["host"] == "github.com" }&.
          fetch("password")

        @github_client ||= Octokit::Client.new(access_token: access_token)
      end
    end
  end
end
