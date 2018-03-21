# frozen_string_literal: true

require "dependabot/dependency_file"
require "dependabot/errors"
require "dependabot/github_client_with_retries"
require "gitlab"

module Dependabot
  module FileFetchers
    class Base
      attr_reader :source, :credentials, :directory, :target_branch

      def self.required_files_in?(_filename_array)
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
          when "gitlab"
            gitlab_client.branch(repo, branch).commit.id
          else raise "Unsupported host '#{host}'."
          end
      end

      private

      def default_branch_for_repo
        @default_branch_for_repo ||=
          case host
          when "github" then github_client.repository(repo).default_branch
          when "gitlab" then gitlab_client.project(repo).default_branch
          else raise "Unsupported host '#{host}'."
          end
      end

      def fetch_file_if_present(filename)
        dir = File.dirname(filename)
        basename = File.basename(filename)
        return unless repo_contents(dir: dir).map(&:name).include?(basename)
        fetch_file_from_host(filename)
      rescue Octokit::NotFound, Gitlab::Error::NotFound
        path = Pathname.new(File.join(directory, filename)).cleanpath.to_path
        raise Dependabot::DependencyFileNotFound, path
      end

      def fetch_file_from_host(filename, type: "file")
        path = Pathname.new(File.join(directory, filename)).cleanpath.to_path

        DependencyFile.new(
          name: Pathname.new(filename).cleanpath.to_path,
          content: fetch_file_content(path),
          directory: directory,
          type: type
        )
      rescue Octokit::NotFound, Gitlab::Error::NotFound
        raise Dependabot::DependencyFileNotFound, path
      end

      def repo_contents(dir: ".")
        path = Pathname.new(File.join(directory, dir)).
               cleanpath.to_path.gsub(%r{^/*}, "")

        @repo_contents ||= {}
        @repo_contents[dir] ||=
          case host
          when "github" then github_repo_contents(path)
          when "gitlab" then gitlab_repo_contents(path)
          else raise "Unsupported host '#{host}'."
          end
      end

      def github_repo_contents(path)
        github_client.contents(repo, path: path, ref: commit).map do |file|
          OpenStruct.new(name: file.name, path: file.path, type: file.type)
        end
      end

      def gitlab_repo_contents(path)
        gitlab_client.
          repo_tree(repo, path: path, ref_name: commit).
          map do |file|
            OpenStruct.new(
              name: file.name,
              path: file.path,
              type: file.type == "blob" ? "file" : file.type
            )
          end
      end

      def fetch_file_content(path)
        path = path.gsub(%r{^/*}, "")

        case host
        when "github"
          tmp = github_client.contents(repo, path: path, ref: commit)
          tmp = tmp.content
          Base64.decode64(tmp).force_encoding("UTF-8").encode
        when "gitlab"
          tmp = gitlab_client.get_file(repo, path, commit).content
          Base64.decode64(tmp).force_encoding("UTF-8").encode
        else raise "Unsupported host '#{host}'."
        end
      rescue NoMethodError
        # Oddly, GitHub sometimes ignores the specified path and returns an
        # array of files instead. Retrying may help.
        @fetch_file_retry_count ||= {}
        @fetch_file_retry_count[path] ||= 0
        retry if @fetch_file_retry_count[path] == 0
        @fetch_file_retry_count[path] += 1
        raise "Array error happening for #{repo}, #{path}, #{commit}."
      end

      def github_client
        access_token =
          credentials.
          find { |cred| cred["host"] == "github.com" }&.
          fetch("password")

        @github_client ||=
          Dependabot::GithubClientWithRetries.new(access_token: access_token)
      end

      def gitlab_client
        access_token =
          credentials.
          find { |cred| cred["host"] == "gitlab.com" }&.
          fetch("password")

        @gitlab_client ||=
          Gitlab.client(
            endpoint: "https://gitlab.com/api/v4",
            private_token: access_token || ""
          )
      end
    end
  end
end
