# frozen_string_literal: true

require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/errors"
require "dependabot/clients/github_with_retries"
require "dependabot/clients/bitbucket"
require "dependabot/clients/gitlab"
require "dependabot/shared_helpers"

# rubocop:disable Metrics/ClassLength
module Dependabot
  module FileFetchers
    class Base
      attr_reader :source, :credentials

      CLIENT_NOT_FOUND_ERRORS = [
        Octokit::NotFound,
        Gitlab::Error::NotFound,
        Dependabot::Clients::Bitbucket::NotFound
      ].freeze

      def self.required_files_in?(_filename_array)
        raise NotImplementedError
      end

      def self.required_files_message
        raise NotImplementedError
      end

      def initialize(source:, credentials:)
        @source = source
        @credentials = credentials

        @submodule_directories = {}
      end

      def repo
        source.repo
      end

      def directory
        Pathname.new(source.directory || "/").cleanpath.to_path
      end

      def target_branch
        source.branch
      end

      def files
        @files ||= fetch_files
      end

      def commit
        branch = target_branch || default_branch_for_repo

        @commit ||= client_for_provider.fetch_commit(repo, branch)
      rescue *CLIENT_NOT_FOUND_ERRORS
        raise Dependabot::BranchNotFound, branch
      rescue Octokit::Conflict => error
        raise unless error.message.include?("Repository is empty")
      end

      private

      def fetch_file_if_present(filename, fetch_submodules: false)
        dir = File.dirname(filename)
        basename = File.basename(filename)

        repo_includes_basename =
          repo_contents(dir: dir, fetch_submodules: fetch_submodules).
          reject { |f| f.type == "dir" }.
          map(&:name).include?(basename)
        return unless repo_includes_basename

        fetch_file_from_host(filename, fetch_submodules: fetch_submodules)
      rescue *CLIENT_NOT_FOUND_ERRORS
        path = Pathname.new(File.join(directory, filename)).cleanpath.to_path
        raise Dependabot::DependencyFileNotFound, path
      end

      def fetch_file_from_host(filename, type: "file", fetch_submodules: false)
        path = Pathname.new(File.join(directory, filename)).cleanpath.to_path

        DependencyFile.new(
          name: Pathname.new(filename).cleanpath.to_path,
          directory: directory,
          type: type,
          content: _fetch_file_content(path, fetch_submodules: fetch_submodules)
        )
      rescue *CLIENT_NOT_FOUND_ERRORS
        raise Dependabot::DependencyFileNotFound, path
      end

      def repo_contents(dir: ".", ignore_base_directory: false,
                        raise_errors: true, fetch_submodules: false)
        dir = File.join(directory, dir) unless ignore_base_directory
        path = Pathname.new(File.join(dir)).cleanpath.to_path.gsub(%r{^/*}, "")

        @repo_contents ||= {}
        @repo_contents[dir] ||= _fetch_repo_contents(
          path,
          raise_errors: raise_errors,
          fetch_submodules: fetch_submodules
        )
      end

      #################################################
      # INTERNAL METHODS (not for use by sub-classes) #
      #################################################

      def _fetch_repo_contents(path, fetch_submodules: false,
                               raise_errors: true)
        path = path.gsub(" ", "%20")
        provider, repo, tmp_path, commit =
          _full_specification_for(path, fetch_submodules: fetch_submodules).
          values_at(:provider, :repo, :path, :commit)

        _fetch_repo_contents_fully_specified(provider, repo, tmp_path, commit)
      rescue *CLIENT_NOT_FOUND_ERRORS
        result = raise_errors ? -> { raise } : -> { [] }
        retrying ||= false

        # If the path changes after calling _fetch_repo_contents_fully_specified
        # it's because we've found a sub-module (and are fetching them). Trigger
        # a retry to get its contents.
        updated_path =
          _full_specification_for(path, fetch_submodules: fetch_submodules).
          fetch(:path)
        retry if updated_path != tmp_path

        return result.call unless fetch_submodules && !retrying

        _find_submodules(path)
        return result.call unless _submodule_for(path)

        retrying = true
        retry
      end

      def _fetch_repo_contents_fully_specified(provider, repo, path, commit)
        case provider
        when "github"
          _github_repo_contents(repo, path, commit)
        when "gitlab"
          _gitlab_repo_contents(repo, path, commit)
        when "bitbucket"
          _bitbucket_repo_contents(repo, path, commit)
        else raise "Unsupported provider '#{provider}'."
        end
      end

      def _github_repo_contents(repo, path, commit)
        path = path.gsub(" ", "%20")
        github_response = github_client.contents(repo, path: path, ref: commit)

        if github_response.respond_to?(:type) &&
           github_response.type == "submodule"
          @submodule_directories[path] = github_response
          raise Octokit::NotFound
        elsif github_response.respond_to?(:type)
          raise Octokit::NotFound
        end

        github_response.map { |f| _build_github_file_struct(f) }
      end

      def _build_github_file_struct(file)
        OpenStruct.new(
          name: file.name,
          path: file.path,
          type: file.type,
          sha: file.sha,
          size: file.size
        )
      end

      def _gitlab_repo_contents(repo, path, commit)
        gitlab_client.
          repo_tree(repo, path: path, ref_name: commit, per_page: 100).
          map do |file|
            OpenStruct.new(
              name: file.name,
              path: file.path,
              type: file.type == "blob" ? "file" : file.type,
              size: 0 # GitLab doesn't return file size
            )
          end
      end

      def _bitbucket_repo_contents(repo, path, commit)
        response = bitbucket_client.fetch_repo_contents(
          repo,
          commit,
          path
        )

        response.map do |file|
          type = case file.fetch("type")
                 when "commit_file" then "file"
                 when "commit_directory" then "dir"
                 else file.fetch("type")
                 end

          OpenStruct.new(
            name: File.basename(file.fetch("path")),
            path: file.fetch("path"),
            type: type,
            size: file.fetch("size", 0)
          )
        end
      end

      def _full_specification_for(path, fetch_submodules:)
        if fetch_submodules && _submodule_for(path) &&
           Source.from_url(
             @submodule_directories[_submodule_for(path)].submodule_git_url
           )
          submodule_details = @submodule_directories[_submodule_for(path)]
          sub_source = Source.from_url(submodule_details.submodule_git_url)
          {
            repo: sub_source.repo,
            commit: submodule_details.sha,
            provider: sub_source.provider,
            path: path.gsub(%r{^#{Regexp.quote(_submodule_for(path))}(/|$)}, "")
          }
        else
          {
            repo: source.repo,
            path: path,
            commit: commit,
            provider: source.provider
          }
        end
      end

      def _fetch_file_content(path, fetch_submodules: false)
        path = path.gsub(%r{^/*}, "")

        provider, repo, path, commit =
          _full_specification_for(path, fetch_submodules: fetch_submodules).
          values_at(:provider, :repo, :path, :commit)

        _fetch_file_content_fully_specified(provider, repo, path, commit)
      rescue *CLIENT_NOT_FOUND_ERRORS
        retrying ||= false

        raise unless fetch_submodules && !retrying && !_submodule_for(path)

        _find_submodules(path)
        raise unless _submodule_for(path)

        retrying = true
        retry
      end

      def _fetch_file_content_fully_specified(provider, repo, path, commit)
        case provider
        when "github"
          _fetch_file_content_from_github(path, repo, commit)
        when "gitlab"
          tmp = gitlab_client.get_file(repo, path, commit).content
          Base64.decode64(tmp).force_encoding("UTF-8").encode
        when "bitbucket"
          bitbucket_client.fetch_file_contents(repo, commit, path)
        else raise "Unsupported provider '#{source.provider}'."
        end
      end

      # rubocop:disable Metrics/AbcSize
      def _fetch_file_content_from_github(path, repo, commit)
        tmp = github_client.contents(repo, path: path, ref: commit)

        raise Octokit::NotFound if tmp.is_a?(Array)

        if tmp.type == "symlink"
          tmp = github_client.contents(
            repo,
            path: tmp.target,
            ref: commit
          )
        end

        Base64.decode64(tmp.content).force_encoding("UTF-8").encode
      rescue Octokit::Forbidden => error
        raise unless error.message.include?("too_large")

        # Fall back to Git Data API to fetch the file
        prefix_dir = directory.gsub(%r{(^/|/$)}, "")
        dir = File.dirname(path).gsub(%r{^/?#{Regexp.escape(prefix_dir)}/?}, "")
        basename = File.basename(path)
        file_details = repo_contents(dir: dir).find { |f| f.name == basename }
        raise unless file_details

        tmp = github_client.blob(repo, file_details.sha)
        return tmp.content if tmp.encoding == "utf-8"

        Base64.decode64(tmp.content).force_encoding("UTF-8").encode
      end
      # rubocop:enable Metrics/AbcSize

      def default_branch_for_repo
        @default_branch_for_repo ||= client_for_provider.
                                     fetch_default_branch(repo)
      rescue *CLIENT_NOT_FOUND_ERRORS
        raise Dependabot::RepoNotFound, source
      end

      # Update the @submodule_directories hash by exploiting a side-effect of
      # recursively calling `repo_contents` for each directory up the tree
      # until a submodule is found
      def _find_submodules(path)
        path = Pathname.new(path).cleanpath.to_path.gsub(%r{^/*}, "")
        dir = File.dirname(path)

        return if [directory, "."].include?(dir)

        repo_contents(
          dir: dir,
          ignore_base_directory: true,
          fetch_submodules: true,
          raise_errors: false
        )
      end

      def _submodule_for(path)
        submodules = @submodule_directories.keys
        submodules.
          select { |k| path.match?(%r{^#{Regexp.quote(k)}(/|$)}) }.
          max_by(&:length)
      end

      def client_for_provider
        case source.provider
        when "github" then github_client
        when "gitlab" then gitlab_client
        when "bitbucket" then bitbucket_client
        else raise "Unsupported provider '#{source.provider}'."
        end
      end

      def github_client
        @github_client ||=
          Dependabot::Clients::GithubWithRetries.for_source(
            source: source,
            credentials: credentials
          )
      end

      def gitlab_client
        @gitlab_client ||=
          Dependabot::Clients::Gitlab.for_source(
            source: source,
            credentials: credentials
          )
      end

      def bitbucket_client
        # TODO: When self-hosted Bitbucket is supported this should use
        # `Bitbucket.for_source`
        @bitbucket_client ||=
          Dependabot::Clients::Bitbucket.
          for_bitbucket_dot_org(credentials: credentials)
      end
    end
  end
end
# rubocop:enable Metrics/ClassLength
