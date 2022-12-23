# frozen_string_literal: true

require "stringio"
require "dependabot/config"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/errors"
require "dependabot/clients/azure"
require "dependabot/clients/codecommit"
require "dependabot/clients/github_with_retries"
require "dependabot/clients/bitbucket_with_retries"
require "dependabot/clients/gitlab_with_retries"
require "dependabot/shared_helpers"

# rubocop:disable Metrics/ClassLength
module Dependabot
  module FileFetchers
    class Base
      attr_reader :source, :credentials, :repo_contents_path, :options

      CLIENT_NOT_FOUND_ERRORS = [
        Octokit::NotFound,
        Gitlab::Error::NotFound,
        Dependabot::Clients::Azure::NotFound,
        Dependabot::Clients::Bitbucket::NotFound,
        Dependabot::Clients::CodeCommit::NotFound
      ].freeze

      GIT_SUBMODULE_INACCESSIBLE_ERROR =
        /^fatal: unable to access '(?<url>.*)': The requested URL returned error: (?<code>\d+)$/
      GIT_SUBMODULE_CLONE_ERROR =
        /^fatal: clone of '(?<url>.*)' into submodule path '.*' failed$/
      GIT_SUBMODULE_ERROR_REGEX = /(#{GIT_SUBMODULE_INACCESSIBLE_ERROR})|(#{GIT_SUBMODULE_CLONE_ERROR})/

      def self.required_files_in?(_filename_array)
        raise NotImplementedError
      end

      def self.required_files_message
        raise NotImplementedError
      end

      # Creates a new FileFetcher for retrieving `DependencyFile`s.
      #
      # Files are typically grabbed individually via the source's API.
      # repo_contents_path is an optional empty directory that will be used
      # to clone the entire source repository on first read.
      #
      # If provided, file _data_ will be loaded from the clone.
      # Submodules and directory listings are _not_ currently supported
      # by repo_contents_path and still use an API trip.
      #
      # options supports custom feature enablement
      def initialize(source:, credentials:, repo_contents_path: nil, options: {})
        @source = source
        @credentials = credentials
        @repo_contents_path = repo_contents_path
        @linked_paths = {}
        @options = options
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
        return cloned_commit if cloned_commit
        return source.commit if source.commit

        branch = target_branch || default_branch_for_repo

        @commit ||= client_for_provider.fetch_commit(repo, branch)
      rescue *CLIENT_NOT_FOUND_ERRORS
        raise Dependabot::BranchNotFound, branch
      rescue Octokit::Conflict => e
        raise unless e.message.include?("Repository is empty")
      end

      # Returns the path to the cloned repo
      def clone_repo_contents
        @clone_repo_contents ||=
          _clone_repo_contents(target_directory: repo_contents_path)
      rescue Dependabot::SharedHelpers::HelperSubprocessFailed => e
        if e.message.include?("fatal: Remote branch #{target_branch} not found in upstream origin")
          raise Dependabot::BranchNotFound, target_branch
        end

        raise Dependabot::RepoNotFound, source
      end

      private

      def fetch_file_if_present(filename, fetch_submodules: false)
        unless repo_contents_path.nil?
          begin
            return load_cloned_file_if_present(filename)
          rescue Dependabot::DependencyFileNotFound
            return
          end
        end

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

      def load_cloned_file_if_present(filename)
        path = Pathname.new(File.join(directory, filename)).cleanpath.to_path
        repo_path = File.join(clone_repo_contents, path)
        raise Dependabot::DependencyFileNotFound, path unless File.exist?(repo_path)

        content = File.read(repo_path)
        type = if File.symlink?(repo_path)
                 symlink_target = File.readlink(repo_path)
                 "symlink"
               else
                 "file"
               end

        DependencyFile.new(
          name: Pathname.new(filename).cleanpath.to_path,
          directory: directory,
          type: type,
          content: content,
          symlink_target: symlink_target
        )
      end

      def fetch_file_from_host(filename, type: "file", fetch_submodules: false)
        return load_cloned_file_if_present(filename) unless repo_contents_path.nil?

        path = Pathname.new(File.join(directory, filename)).cleanpath.to_path
        content = _fetch_file_content(path, fetch_submodules: fetch_submodules)
        type = "symlink" if @linked_paths.key?(path.gsub(%r{^/}, ""))

        DependencyFile.new(
          name: Pathname.new(filename).cleanpath.to_path,
          directory: directory,
          type: type,
          content: content,
          symlink_target: @linked_paths.dig(path.gsub(%r{^/}, ""), :path)
        )
      rescue *CLIENT_NOT_FOUND_ERRORS
        raise Dependabot::DependencyFileNotFound, path
      end

      def repo_contents(dir: ".", ignore_base_directory: false,
                        raise_errors: true, fetch_submodules: false)
        dir = File.join(directory, dir) unless ignore_base_directory
        path = Pathname.new(File.join(dir)).cleanpath.to_path.gsub(%r{^/*}, "")

        @repo_contents ||= {}
        @repo_contents[dir] ||= if repo_contents_path
                                  _cloned_repo_contents(path)
                                else
                                  _fetch_repo_contents(path, raise_errors: raise_errors,
                                                             fetch_submodules: fetch_submodules)
                                end
      end

      def cloned_commit
        return if repo_contents_path.nil? || !File.directory?(File.join(repo_contents_path, ".git"))

        SharedHelpers.with_git_configured(credentials: credentials) do
          Dir.chdir(repo_contents_path) do
            return SharedHelpers.run_shell_command("git rev-parse HEAD")&.strip
          end
        end
      end

      def default_branch_for_repo
        @default_branch_for_repo ||= client_for_provider.
                                     fetch_default_branch(repo)
      rescue *CLIENT_NOT_FOUND_ERRORS
        raise Dependabot::RepoNotFound, source
      end

      def update_linked_paths(repo, path, commit, github_response)
        case github_response.type
        when "submodule"
          sub_source = Source.from_url(github_response.submodule_git_url)
          return unless sub_source

          @linked_paths[path] = {
            repo: sub_source.repo,
            provider: sub_source.provider,
            commit: github_response.sha,
            path: "/"
          }
        when "symlink"
          updated_path = File.join(File.dirname(path), github_response.target)
          @linked_paths[path] = {
            repo: repo,
            provider: "github",
            commit: commit,
            path: Pathname.new(updated_path).cleanpath.to_path
          }
        end
      end

      def recurse_submodules_when_cloning?
        false
      end

      def client_for_provider
        case source.provider
        when "github" then github_client
        when "gitlab" then gitlab_client
        when "azure" then azure_client
        when "bitbucket" then bitbucket_client
        when "codecommit" then codecommit_client
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
          Dependabot::Clients::GitlabWithRetries.for_source(
            source: source,
            credentials: credentials
          )
      end

      def azure_client
        @azure_client ||=
          Dependabot::Clients::Azure.
          for_source(source: source, credentials: credentials)
      end

      def bitbucket_client
        # TODO: When self-hosted Bitbucket is supported this should use
        # `Bitbucket.for_source`
        @bitbucket_client ||=
          Dependabot::Clients::BitbucketWithRetries.
          for_bitbucket_dot_org(credentials: credentials)
      end

      def codecommit_client
        @codecommit_client ||=
          Dependabot::Clients::CodeCommit.
          for_source(source: source, credentials: credentials)
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

        _find_linked_dirs(path)
        return result.call unless _linked_dir_for(path)

        retrying = true
        retry
      end

      def _fetch_repo_contents_fully_specified(provider, repo, path, commit)
        case provider
        when "github"
          _github_repo_contents(repo, path, commit)
        when "gitlab"
          _gitlab_repo_contents(repo, path, commit)
        when "azure"
          _azure_repo_contents(path, commit)
        when "bitbucket"
          _bitbucket_repo_contents(repo, path, commit)
        when "codecommit"
          _codecommit_repo_contents(repo, path, commit)
        else raise "Unsupported provider '#{provider}'."
        end
      end

      def _github_repo_contents(repo, path, commit)
        path = path.gsub(" ", "%20")
        github_response = github_client.contents(repo, path: path, ref: commit)

        if github_response.respond_to?(:type)
          update_linked_paths(repo, path, commit, github_response)
          raise Octokit::NotFound
        end

        github_response.map { |f| _build_github_file_struct(f) }
      end

      def _cloned_repo_contents(relative_path)
        repo_path = File.join(clone_repo_contents, relative_path)
        return [] unless Dir.exist?(repo_path)

        Dir.entries(repo_path).filter_map do |name|
          next if name == "." || name == ".."

          absolute_path = File.join(repo_path, name)
          type = if File.symlink?(absolute_path)
                   "symlink"
                 elsif Dir.exist?(absolute_path)
                   "dir"
                 else
                   "file"
                 end

          OpenStruct.new(
            name: name,
            path: Pathname.new(File.join(relative_path, name)).cleanpath.to_path,
            type: type,
            size: 0 # NOTE: added for parity with github contents API
          )
        end
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
            # GitLab API essentially returns the output from `git ls-tree`
            type = case file.type
                   when "blob" then "file"
                   when "tree" then "dir"
                   when "commit" then "submodule"
                   else file.fetch("type")
                   end

            OpenStruct.new(
              name: file.name,
              path: file.path,
              type: type,
              size: 0 # GitLab doesn't return file size
            )
          end
      end

      def _azure_repo_contents(path, commit)
        response = azure_client.fetch_repo_contents(commit, path)

        response.map do |entry|
          type = case entry.fetch("gitObjectType")
                 when "blob" then "file"
                 when "tree" then "dir"
                 else entry.fetch("gitObjectType")
                 end

          OpenStruct.new(
            name: File.basename(entry.fetch("relativePath")),
            path: entry.fetch("relativePath"),
            type: type,
            size: entry.fetch("size")
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

      def _codecommit_repo_contents(repo, path, commit)
        response = codecommit_client.fetch_repo_contents(
          repo,
          commit,
          path
        )

        response.files.map do |file|
          OpenStruct.new(
            name: File.basename(file.relative_path),
            path: file.relative_path,
            type: "file",
            size: 0 # file size would require new api call per file..
          )
        end
      end

      def _full_specification_for(path, fetch_submodules:)
        if fetch_submodules && _linked_dir_for(path)
          linked_dir_details = @linked_paths[_linked_dir_for(path)]
          sub_path =
            path.gsub(%r{^#{Regexp.quote(_linked_dir_for(path))}(/|$)}, "")
          new_path =
            Pathname.new(File.join(linked_dir_details.fetch(:path), sub_path)).
            cleanpath.to_path.
            gsub(%r{^/}, "")
          {
            repo: linked_dir_details.fetch(:repo),
            commit: linked_dir_details.fetch(:commit),
            provider: linked_dir_details.fetch(:provider),
            path: new_path
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

        raise unless fetch_submodules && !retrying && !_linked_dir_for(path)

        _find_linked_dirs(path)
        raise unless _linked_dir_for(path)

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
        when "azure"
          azure_client.fetch_file_contents(commit, path)
        when "bitbucket"
          bitbucket_client.fetch_file_contents(repo, commit, path)
        when "codecommit"
          codecommit_client.fetch_file_contents(repo, commit, path)
        else raise "Unsupported provider '#{source.provider}'."
        end
      end

      # rubocop:disable Metrics/AbcSize
      def _fetch_file_content_from_github(path, repo, commit)
        tmp = github_client.contents(repo, path: path, ref: commit)

        raise Octokit::NotFound if tmp.is_a?(Array)

        if tmp.type == "symlink"
          @linked_paths[path] = {
            repo: repo,
            provider: "github",
            commit: commit,
            path: Pathname.new(tmp.target).cleanpath.to_path
          }
          tmp = github_client.contents(
            repo,
            path: Pathname.new(tmp.target).cleanpath.to_path,
            ref: commit
          )
        end

        if tmp.content == ""
          # The file may have exceeded the 1MB limit
          # see https://github.blog/changelog/2022-05-03-increased-file-size-limit-when-retrieving-file-contents-via-rest-api/
          github_client.contents(repo, path: path, ref: commit, accept: "application/vnd.github.v3.raw")
        else
          Base64.decode64(tmp.content).force_encoding("UTF-8").encode
        end
      rescue Octokit::Forbidden => e
        raise unless e.message.include?("too_large")

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

      # Update the @linked_paths hash by exploiting a side-effect of
      # recursively calling `repo_contents` for each directory up the tree
      # until a submodule or symlink is found
      def _find_linked_dirs(path)
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

      def _linked_dir_for(path)
        linked_dirs = @linked_paths.keys
        linked_dirs.
          select { |k| path.match?(%r{^#{Regexp.quote(k)}(/|$)}) }.
          max_by(&:length)
      end

      # rubocop:disable Metrics/AbcSize
      # rubocop:disable Metrics/MethodLength
      # rubocop:disable Metrics/PerceivedComplexity
      # rubocop:disable Metrics/BlockLength
      def _clone_repo_contents(target_directory:)
        SharedHelpers.with_git_configured(credentials: credentials) do
          path = target_directory || File.join("tmp", source.repo)
          # Assume we're retrying the same branch, or that a `target_directory`
          # is specified when retrying a different branch.
          return path if Dir.exist?(File.join(path, ".git"))

          FileUtils.mkdir_p(path)

          clone_options = StringIO.new
          clone_options << "--no-tags --depth 1"
          clone_options << if recurse_submodules_when_cloning?
                             " --recurse-submodules --shallow-submodules"
                           else
                             " --no-recurse-submodules"
                           end
          clone_options << " --branch #{source.branch} --single-branch" if source.branch

          submodule_cloning_failed = false
          begin
            SharedHelpers.run_shell_command(
              <<~CMD
                git clone #{clone_options.string} #{source.url} #{path}
              CMD
            )
          rescue SharedHelpers::HelperSubprocessFailed => e
            raise unless GIT_SUBMODULE_ERROR_REGEX && e.message.downcase.include?("submodule")

            submodule_cloning_failed = true
            match = e.message.match(GIT_SUBMODULE_ERROR_REGEX)
            url = match.named_captures["url"]
            code = match.named_captures["code"]

            # Submodules might be in the repo but unrelated to dependencies,
            # so ignoring this error to try the update anyway since the base repo exists.
            Dependabot.logger.error("Cloning of submodule failed: #{url} error: #{code || 'unknown'}")
          end

          if source.commit
            # This code will only be called for testing. Production will never pass a commit
            # since Dependabot always wants to use the latest commit on a branch.
            Dir.chdir(path) do
              fetch_options = StringIO.new
              fetch_options << "--depth 1"
              fetch_options << if recurse_submodules_when_cloning? && !submodule_cloning_failed
                                 " --recurse-submodules=on-demand"
                               else
                                 " --no-recurse-submodules"
                               end
              # Need to fetch the commit due to the --depth 1 above.
              SharedHelpers.run_shell_command("git fetch #{fetch_options.string} origin #{source.commit}")

              reset_options = StringIO.new
              reset_options << "--hard"
              reset_options << if recurse_submodules_when_cloning? && !submodule_cloning_failed
                                 " --recurse-submodules"
                               else
                                 " --no-recurse-submodules"
                               end
              # Set HEAD to this commit so later calls so git reset HEAD will work.
              SharedHelpers.run_shell_command("git reset #{reset_options.string} #{source.commit}")
            end
          end

          path
        end
      end
      # rubocop:enable Metrics/AbcSize
      # rubocop:enable Metrics/MethodLength
      # rubocop:enable Metrics/PerceivedComplexity
      # rubocop:enable Metrics/BlockLength
    end
  end
end
# rubocop:enable Metrics/ClassLength
