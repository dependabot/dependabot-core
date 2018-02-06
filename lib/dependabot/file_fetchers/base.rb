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
        branch = target_branch || default_branch_for_repo

        @commit ||=
          case host
          when "github"
            github_client.ref(repo, "heads/#{branch}").object.sha
          else raise "Unsupported host '#{host}'."
          end
      end

      private

      def default_branch_for_repo
        @default_branch ||=
          case host
          when "github" then github_client.repository(repo).default_branch
          else raise "Unsupported host '#{host}'."
          end
      end

      def fetch_file_if_present(filename)
        dir = File.dirname(filename)
        basename = File.basename(filename)
        return unless repo_contents(dir: dir).map(&:name).include?(basename)
        fetch_file_from_host(filename)
      rescue Octokit::NotFound
        path = Pathname.new(File.join(directory, filename)).cleanpath.to_path
        raise Dependabot::DependencyFileNotFound, path
      end

      def fetch_file_from_host(filename, type: "file")
        path = Pathname.new(File.join(directory, filename)).cleanpath.to_path

        # Currently only GitHub is supported. In future, supporting other
        # hosting providers would be straightforward.
        content =
          case host
          when "github"
            tmp = github_client.contents(repo, path: path, ref: commit).content
            Base64.decode64(tmp).force_encoding("UTF-8").encode
          else raise "Unsupported host '#{host}'."
          end

        DependencyFile.new(
          name: Pathname.new(filename).cleanpath.to_path,
          content: content,
          directory: directory,
          type: type
        )
      rescue Octokit::NotFound
        raise Dependabot::DependencyFileNotFound, path
      end

      def repo_contents(dir: ".")
        path = Pathname.new(File.join(directory, dir)).cleanpath.to_path

        @repo_contents ||= {}
        @repo_contents[dir] ||=
          case host
          when "github"
            github_client.contents(repo, path: path, ref: commit)
          else raise "Unsupported host '#{host}'."
          end
      end

      # One day this class, and all others, will be provider agnostic. For
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
