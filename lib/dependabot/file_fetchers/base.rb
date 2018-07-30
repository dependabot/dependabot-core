# frozen_string_literal: true

require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/errors"
require "dependabot/github_client_with_retries"
require "gitlab"

module Dependabot
  module FileFetchers
    class Base
      attr_reader :source, :credentials, :target_branch

      def self.required_files_in?(_filename_array)
        raise NotImplementedError
      end

      def self.required_files_message
        raise NotImplementedError
      end

      def initialize(source:, credentials:, target_branch: nil)
        @source = source
        @credentials = credentials
        @target_branch = target_branch
        @submodule_directories = {}
      end

      def repo
        source.repo
      end

      def directory
        source.directory || "/"
      end

      def files
        @files ||= fetch_files
      end

      def commit
        branch = target_branch || default_branch_for_repo

        @commit ||=
          case source.provider
          when "github"
            github_client_for_source.ref(repo, "heads/#{branch}").object.sha
          when "gitlab"
            gitlab_client.branch(repo, branch).commit.id
          else raise "Unsupported provider '#{source.provider}'."
          end
      rescue Octokit::NotFound
        raise Dependabot::BranchNotFound, branch
      end

      private

      def default_branch_for_repo
        @default_branch_for_repo ||=
          case source.provider
          when "github"
            github_client_for_source.repository(repo).default_branch
          when "gitlab"
            gitlab_client.project(repo).default_branch
          else raise "Unsupported provider '#{source.provider}'."
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

      def fetch_file_from_host_or_submodule(filename, type: "file")
        fetch_file_from_host(filename, type: type)
      rescue Dependabot::DependencyFileNotFound => error
        begin
          repo_contents(dir: File.dirname(filename))
        rescue StandardError
          raise error
        end

        fetch_file_from_host(filename, type: type)
      end

      def repo_contents(dir: ".")
        path = Pathname.new(File.join(directory, dir)).
               cleanpath.to_path.gsub(%r{^/*}, "")

        # Don't fetch contents of repos nested in submodules
        submods = @submodule_directories
        if submods.keys.any? { |k| path.match?(%r{#{Regexp.quote(k)}(/|$)}) }
          return []
        end

        @repo_contents ||= {}
        @repo_contents[dir] ||=
          case source.provider
          when "github" then github_repo_contents(path)
          when "gitlab" then gitlab_repo_contents(path)
          else raise "Unsupported provider '#{source.provider}'."
          end
      end

      def github_repo_contents(path)
        github_response = github_client_for_source.
                          contents(repo, path: path, ref: commit)

        if github_response.respond_to?(:type) &&
           github_response.type == "submodule"
          @submodule_directories[path] = github_response

          sub_source = Source.from_url(github_response.submodule_git_url)
          github_response = github_client_for_source.
                            contents(sub_source.repo, ref: github_response.sha)
        end

        github_response.map do |f|
          OpenStruct.new(name: f.name, path: f.path, type: f.type, sha: f.sha)
        end
      end

      def gitlab_repo_contents(path)
        gitlab_client.
          repo_tree(repo, path: path, ref_name: commit, per_page: 100).
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
        dir = Pathname.new(path).dirname.to_path.gsub(%r{^/*}, "")

        if @submodule_directories.key?(dir)
          return fetch_submodule_file_content(path)
        end

        case source.provider
        when "github" then fetch_file_content_from_github(path, repo, commit)
        when "gitlab"
          tmp = gitlab_client.get_file(repo, path, commit).content
          Base64.decode64(tmp).force_encoding("UTF-8").encode
        else raise "Unsupported provider '#{source.provider}'."
        end
      end

      def fetch_submodule_file_content(path)
        path = path.gsub(%r{^/*}, "")
        dir = Pathname.new(path).dirname.to_path.gsub(%r{^/*}, "")
        submodule = @submodule_directories[dir]

        provider = Source.from_url(submodule.submodule_git_url).provider
        repo = Source.from_url(submodule.submodule_git_url).repo
        commit = submodule.sha
        path = path.gsub("#{dir}/", "")

        case provider
        when "github" then fetch_file_content_from_github(path, repo, commit)
        when "gitlab"
          tmp = gitlab_client.get_file(repo, path, commit).content
          Base64.decode64(tmp).force_encoding("UTF-8").encode
        else raise "Unsupported provider '#{provider}'."
        end
      end

      # rubocop:disable Metrics/AbcSize
      def fetch_file_content_from_github(path, repo, commit)
        tmp = github_client_for_source.contents(repo, path: path, ref: commit)
        Base64.decode64(tmp.content).force_encoding("UTF-8").encode
      rescue Octokit::Forbidden => error
        raise unless error.message.include?("too_large")

        # Fall back to Git Data API to fetch the file
        prefix_dir = directory.gsub(%r{(^/|/$)}, "")
        dir = File.dirname(path).gsub(%r{^/?#{Regexp.escape(prefix_dir)}/?}, "")
        basename = File.basename(path)
        file_details = repo_contents(dir: dir).find { |f| f.name == basename }
        raise unless file_details

        tmp = github_client_for_source.blob(repo, file_details.sha)
        return tmp.content if tmp.encoding == "utf-8"
        Base64.decode64(tmp.content).force_encoding("UTF-8").encode
      end
      # rubocop:enable Metrics/AbcSize

      def github_client_for_source
        @github_client_for_source ||=
          Dependabot::GithubClientWithRetries.for_source(
            source: source,
            credentials: credentials
          )
      end

      def gitlab_client
        access_token =
          credentials.
          select { |cred| cred["type"] == "git_source" }.
          find { |cred| cred["host"] == source.hostname }&.
          fetch("password")

        @gitlab_client ||=
          Gitlab.client(
            endpoint: source.api_endpoint,
            private_token: access_token || ""
          )
      end
    end
  end
end
