# typed: strict
# frozen_string_literal: true

require "stringio"
require "sorbet-runtime"
require "dependabot/config"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/errors"
require "dependabot/credential"
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
      extend T::Sig
      extend T::Helpers

      abstract!

      sig { returns(Dependabot::Source) }
      attr_reader :source

      sig { returns(T::Array[Dependabot::Credential]) }
      attr_reader :credentials

      sig { returns(T.nilable(String)) }
      attr_reader :repo_contents_path

      sig { returns(T::Hash[String, String]) }
      attr_reader :options

      CLIENT_NOT_FOUND_ERRORS = T.let(
        [
          Octokit::NotFound,
          Gitlab::Error::NotFound,
          Dependabot::Clients::Azure::NotFound,
          Dependabot::Clients::Bitbucket::NotFound,
          Dependabot::Clients::CodeCommit::NotFound
        ].freeze,
        T::Array[T.class_of(StandardError)]
      )

      GIT_SUBMODULE_INACCESSIBLE_ERROR =
        /^fatal: unable to access '(?<url>.*)': The requested URL returned error: (?<code>\d+)$/
      GIT_SUBMODULE_CLONE_ERROR =
        /^fatal: clone of '(?<url>.*)' into submodule path '.*' failed$/
      GIT_SUBMODULE_ERROR_REGEX = /(#{GIT_SUBMODULE_INACCESSIBLE_ERROR})|(#{GIT_SUBMODULE_CLONE_ERROR})/
      GIT_RETRYABLE_ERRORS =
        T.let(
          [
            /remote error: Internal Server Error/,
            /fatal: Couldn\'t find remote ref/,
            %r{git fetch_pack: expected ACK/NAK, got},
            /protocol error: bad pack header/,
            /The remote end hung up unexpectedly/,
            /TLS packet with unexpected length was received/,
            /RPC failed; result=\d+, HTTP code = \d+/,
            /Connection timed out/,
            /Connection reset by peer/,
            /Unable to look up/,
            /Couldn\'t resolve host/,
            /The requested URL returned error: (429|5\d{2})/
          ].freeze,
          T::Array[Regexp]
        )

      sig { overridable.params(filenames: T::Array[String]).returns(T::Boolean) }
      def self.required_files_in?(filenames)
        filenames.any?
      end

      sig { overridable.returns(String) }
      def self.required_files_message
        "Required files are missing from configured directory"
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
      sig do
        params(
          source: Dependabot::Source,
          credentials: T::Array[Dependabot::Credential],
          repo_contents_path: T.nilable(String),
          options: T::Hash[String, String]
        )
          .void
      end
      def initialize(source:, credentials:, repo_contents_path: nil, options: {})
        @source = source
        @credentials = credentials
        @repo_contents_path = repo_contents_path
        @linked_paths = T.let({}, T::Hash[T.untyped, T.untyped])
        @submodules = T.let([], T::Array[T.untyped])
        @options = options

        @files = T.let([], T::Array[DependencyFile])
      end

      sig { returns(String) }
      def repo
        source.repo
      end

      sig { returns(String) }
      def directory
        Pathname.new(source.directory || "/").cleanpath.to_path
      end

      sig { returns(T.nilable(String)) }
      def target_branch
        source.branch
      end

      sig { returns(T::Array[DependencyFile]) }
      def files
        return @files if @files.any?

        files = fetch_files.compact
        raise Dependabot::DependencyFileNotFound.new(nil, "No files found in #{directory}") unless files.any?

        unless self.class.required_files_in?(files.map(&:name))
          raise DependencyFileNotFound.new(nil, self.class.required_files_message)
        end

        @files = files
      end

      sig { abstract.returns(T::Array[DependencyFile]) }
      def fetch_files; end

      sig { returns(T.nilable(String)) }
      def commit
        return T.must(cloned_commit) if cloned_commit
        return T.must(source.commit) if source.commit

        branch = target_branch || default_branch_for_repo

        @commit ||= T.let(T.unsafe(client_for_provider).fetch_commit(repo, branch), T.nilable(String))
      rescue *CLIENT_NOT_FOUND_ERRORS
        raise Dependabot::BranchNotFound, branch
      rescue Octokit::Conflict => e
        raise unless e.message.include?("Repository is empty")
      end

      # Returns the path to the cloned repo
      sig { overridable.returns(String) }
      def clone_repo_contents
        @clone_repo_contents ||= T.let(
          _clone_repo_contents(target_directory: repo_contents_path),
          T.nilable(String)
        )
      rescue Dependabot::SharedHelpers::HelperSubprocessFailed => e
        if e.message.include?("fatal: Remote branch #{target_branch} not found in upstream origin")
          raise Dependabot::BranchNotFound, target_branch
        elsif e.message.include?("No space left on device")
          raise Dependabot::OutOfDisk
        end

        raise Dependabot::RepoNotFound.new(source, e.message)
      end

      sig { overridable.returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def ecosystem_versions; end

      private

      sig { params(name: String).returns(T.nilable(Dependabot::DependencyFile)) }
      def fetch_support_file(name)
        fetch_file_if_present(name)&.tap { |f| f.support_file = true }
      end

      sig { params(filename: String, fetch_submodules: T::Boolean).returns(T.nilable(DependencyFile)) }
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
          repo_contents(dir: dir, fetch_submodules: fetch_submodules)
          .reject { |f| f.type == "dir" }
          .map(&:name).include?(basename)
        return unless repo_includes_basename

        fetch_file_from_host(filename, fetch_submodules: fetch_submodules)
      rescue *CLIENT_NOT_FOUND_ERRORS
        nil
      end

      sig { params(filename: T.any(Pathname, String)).returns(Dependabot::DependencyFile) }
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
          symlink_target: symlink_target,
          support_file: in_submodule?(path)
        )
      end

      sig do
        params(
          filename: T.any(Pathname, String),
          type: String,
          fetch_submodules: T::Boolean
        )
          .returns(Dependabot::DependencyFile)
      end
      def fetch_file_from_host(filename, type: "file", fetch_submodules: false)
        return load_cloned_file_if_present(filename) unless repo_contents_path.nil?

        path = Pathname.new(File.join(directory, filename)).cleanpath.to_path
        content = _fetch_file_content(path, fetch_submodules: fetch_submodules)
        clean_path = path.gsub(%r{^/}, "")

        linked_path = symlinked_subpath(clean_path)
        type = "symlink" if linked_path
        symlink_target = clean_path.sub(T.must(linked_path), @linked_paths.dig(linked_path, :path)) if type == "symlink"

        DependencyFile.new(
          name: Pathname.new(filename).cleanpath.to_path,
          directory: directory,
          type: type,
          content: content,
          symlink_target: symlink_target
        )
      rescue *CLIENT_NOT_FOUND_ERRORS
        raise Dependabot::DependencyFileNotFound, path
      end

      # Finds the first subpath in path that is a symlink
      sig { params(path: String).returns(T.nilable(String)) }
      def symlinked_subpath(path)
        subpaths(path).find { |subpath| @linked_paths.key?(subpath) }
      end

      sig { params(path: String).returns(T::Boolean) }
      def in_submodule?(path)
        subpaths(path.delete_prefix("/")).any? { |subpath| @submodules.include?(subpath) }
      end

      # Given a "foo/bar/baz" path, returns ["foo", "foo/bar", "foo/bar/baz"]
      sig { params(path: String).returns(T::Array[String]) }
      def subpaths(path)
        components = path.split("/")
        components.map { |component| T.must(components[0..components.index(component)]).join("/") }
      end

      sig do
        params(
          dir: T.any(Pathname, String),
          ignore_base_directory: T::Boolean,
          raise_errors: T::Boolean,
          fetch_submodules: T::Boolean
        )
          .returns(T::Array[T.untyped])
      end
      def repo_contents(dir: ".", ignore_base_directory: false,
                        raise_errors: true, fetch_submodules: false)
        dir = File.join(directory, dir) unless ignore_base_directory
        path = Pathname.new(dir).cleanpath.to_path.gsub(%r{^/*}, "")

        @repo_contents ||= T.let({}, T.nilable(T::Hash[String, T::Array[T.untyped]]))
        @repo_contents[dir.to_s] ||= if repo_contents_path
                                       _cloned_repo_contents(path)
                                     else
                                       _fetch_repo_contents(path, raise_errors: raise_errors,
                                                                  fetch_submodules: fetch_submodules)
                                     end
      end

      sig { returns(T.nilable(String)) }
      def cloned_commit
        return if repo_contents_path.nil? || !File.directory?(File.join(repo_contents_path, ".git"))

        SharedHelpers.with_git_configured(credentials: credentials) do
          Dir.chdir(T.must(repo_contents_path)) do
            return SharedHelpers.run_shell_command("git rev-parse HEAD").strip
          end
        end
      end

      sig { returns(String) }
      def default_branch_for_repo
        @default_branch_for_repo ||= T.let(T.unsafe(client_for_provider).fetch_default_branch(repo), T.nilable(String))
      rescue *CLIENT_NOT_FOUND_ERRORS
        raise Dependabot::RepoNotFound, source
      end

      sig do
        params(
          repo: String,
          path: String,
          commit: String,
          github_response: Sawyer::Resource
        )
          .returns(T.nilable(T::Hash[String, T.untyped]))
      end
      def update_linked_paths(repo, path, commit, github_response)
        case T.unsafe(github_response).type
        when "submodule"
          sub_source = Source.from_url(T.unsafe(github_response).submodule_git_url)
          return unless sub_source

          @linked_paths[path] = {
            repo: sub_source.repo,
            provider: sub_source.provider,
            commit: T.unsafe(github_response).sha,
            path: "/"
          }
        when "symlink"
          updated_path = File.join(File.dirname(path), T.unsafe(github_response).target)
          @linked_paths[path] = {
            repo: repo,
            provider: "github",
            commit: commit,
            path: Pathname.new(updated_path).cleanpath.to_path
          }
        end
      end

      sig do
        returns(
          T.any(
            Dependabot::Clients::GithubWithRetries,
            Dependabot::Clients::GitlabWithRetries,
            Dependabot::Clients::Azure,
            Dependabot::Clients::BitbucketWithRetries,
            Dependabot::Clients::CodeCommit
          )
        )
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

      sig { returns(Dependabot::Clients::GithubWithRetries) }
      def github_client
        @github_client ||=
          T.let(
            Dependabot::Clients::GithubWithRetries.for_source(
              source: source,
              credentials: credentials
            ),
            T.nilable(Dependabot::Clients::GithubWithRetries)
          )
      end

      sig { returns(Dependabot::Clients::GitlabWithRetries) }
      def gitlab_client
        @gitlab_client ||=
          T.let(
            Dependabot::Clients::GitlabWithRetries.for_source(
              source: source,
              credentials: credentials
            ),
            T.nilable(Dependabot::Clients::GitlabWithRetries)
          )
      end

      sig { returns(Dependabot::Clients::Azure) }
      def azure_client
        @azure_client ||=
          T.let(
            Dependabot::Clients::Azure.for_source(
              source: source,
              credentials: credentials
            ),
            T.nilable(Dependabot::Clients::Azure)
          )
      end

      sig { returns(Dependabot::Clients::BitbucketWithRetries) }
      def bitbucket_client
        # TODO: When self-hosted Bitbucket is supported this should use
        # `Bitbucket.for_source`
        @bitbucket_client ||=
          T.let(
            Dependabot::Clients::BitbucketWithRetries.for_bitbucket_dot_org(
              credentials: credentials
            ),
            T.nilable(Dependabot::Clients::BitbucketWithRetries)
          )
      end

      sig { returns(Dependabot::Clients::CodeCommit) }
      def codecommit_client
        @codecommit_client ||=
          T.let(
            Dependabot::Clients::CodeCommit.for_source(
              source: source,
              credentials: credentials
            ),
            T.nilable(Dependabot::Clients::CodeCommit)
          )
      end

      #################################################
      # INTERNAL METHODS (not for use by sub-classes) #
      #################################################

      sig { params(path: String, fetch_submodules: T::Boolean, raise_errors: T::Boolean).returns(T::Array[OpenStruct]) }
      def _fetch_repo_contents(path, fetch_submodules: false, raise_errors: true)
        path = path.gsub(" ", "%20")
        provider, repo, tmp_path, commit =
          _full_specification_for(path, fetch_submodules: fetch_submodules)
          .values_at(:provider, :repo, :path, :commit)

        _fetch_repo_contents_fully_specified(provider, repo, tmp_path, commit)
      rescue *CLIENT_NOT_FOUND_ERRORS
        raise Dependabot::DirectoryNotFound, directory if path == directory.gsub(%r{^/*}, "")

        result = raise_errors ? -> { raise } : -> { [] }
        retrying ||= false

        # If the path changes after calling _fetch_repo_contents_fully_specified
        # it's because we've found a sub-module (and are fetching them). Trigger
        # a retry to get its contents.
        updated_path =
          _full_specification_for(path, fetch_submodules: fetch_submodules)
          .fetch(:path)
        retry if updated_path != tmp_path

        return result.call unless fetch_submodules && !retrying

        _find_linked_dirs(path)
        return result.call unless _linked_dir_for(path)

        retrying = true
        retry
      end

      sig { params(provider: String, repo: String, path: String, commit: String).returns(T::Array[OpenStruct]) }
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

      sig { params(repo: String, path: String, commit: String).returns(T::Array[OpenStruct]) }
      def _github_repo_contents(repo, path, commit)
        path = path.gsub(" ", "%20")
        github_response = T.unsafe(github_client).contents(repo, path: path, ref: commit)

        if github_response.respond_to?(:type)
          update_linked_paths(repo, path, commit, github_response)
          raise Octokit::NotFound
        end

        github_response.map { |f| _build_github_file_struct(f) }
      end

      sig { params(relative_path: String).returns(T::Array[OpenStruct]) }
      def _cloned_repo_contents(relative_path)
        repo_path = File.join(clone_repo_contents, relative_path)
        return [] unless Dir.exist?(repo_path)

        Dir.entries(repo_path).sort.filter_map do |name|
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

      sig { params(file: Sawyer::Resource).returns(OpenStruct) }
      def _build_github_file_struct(file)
        OpenStruct.new(
          name: T.unsafe(file).name,
          path: T.unsafe(file).path,
          type: T.unsafe(file).type,
          sha: T.unsafe(file).sha,
          size: T.unsafe(file).size
        )
      end

      sig { params(repo: String, path: String, commit: String).returns(T::Array[OpenStruct]) }
      def _gitlab_repo_contents(repo, path, commit)
        T.unsafe(gitlab_client)
         .repo_tree(repo, path: path, ref: commit, per_page: 100)
         .map do |file|
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

      sig { params(path: String, commit: String).returns(T::Array[OpenStruct]) }
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

      sig { params(repo: String, path: String, commit: String).returns(T::Array[OpenStruct]) }
      def _bitbucket_repo_contents(repo, path, commit)
        response = T.unsafe(bitbucket_client)
                    .fetch_repo_contents(
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

      sig { params(repo: String, path: String, commit: String).returns(T::Array[OpenStruct]) }
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

      sig { params(path: String, fetch_submodules: T::Boolean).returns(T::Hash[Symbol, T.untyped]) }
      def _full_specification_for(path, fetch_submodules:)
        if fetch_submodules && _linked_dir_for(path)
          linked_dir_details = @linked_paths[_linked_dir_for(path)]
          sub_path =
            path.gsub(%r{^#{Regexp.quote(T.must(_linked_dir_for(path)))}(/|$)}, "")
          new_path =
            Pathname.new(File.join(linked_dir_details.fetch(:path), sub_path))
                    .cleanpath.to_path
                    .gsub(%r{^/}, "")
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

      sig { params(path: String, fetch_submodules: T::Boolean).returns(String) }
      def _fetch_file_content(path, fetch_submodules: false)
        path = path.gsub(%r{^/*}, "")

        provider, repo, path, commit =
          _full_specification_for(path, fetch_submodules: fetch_submodules)
          .values_at(:provider, :repo, :path, :commit)

        _fetch_file_content_fully_specified(provider, repo, path, commit)
      rescue *CLIENT_NOT_FOUND_ERRORS
        retrying ||= false

        raise unless fetch_submodules && !retrying && !_linked_dir_for(path)

        _find_linked_dirs(path)
        raise unless _linked_dir_for(path)

        retrying = true
        retry
      end

      sig { params(provider: String, repo: String, path: String, commit: String).returns(String) }
      def _fetch_file_content_fully_specified(provider, repo, path, commit)
        case provider
        when "github"
          _fetch_file_content_from_github(path, repo, commit)
        when "gitlab"
          tmp = T.unsafe(gitlab_client).get_file(repo, path, commit).content
          decode_binary_string(tmp)
        when "azure"
          azure_client.fetch_file_contents(commit, path)
        when "bitbucket"
          T.unsafe(bitbucket_client).fetch_file_contents(repo, commit, path)
        when "codecommit"
          codecommit_client.fetch_file_contents(repo, commit, path)
        else raise "Unsupported provider '#{source.provider}'."
        end
      end

      # rubocop:disable Metrics/AbcSize
      sig { params(path: String, repo: String, commit: String).returns(String) }
      def _fetch_file_content_from_github(path, repo, commit)
        tmp = T.unsafe(github_client).contents(repo, path: path, ref: commit)

        raise Octokit::NotFound if tmp.is_a?(Array)

        if tmp.type == "symlink"
          @linked_paths[path] = {
            repo: repo,
            provider: "github",
            commit: commit,
            path: Pathname.new(tmp.target).cleanpath.to_path
          }
          tmp = T.unsafe(github_client).contents(
            repo,
            path: Pathname.new(tmp.target).cleanpath.to_path,
            ref: commit
          )
        end

        if tmp.content == ""
          # The file may have exceeded the 1MB limit
          # see https://github.blog/changelog/2022-05-03-increased-file-size-limit-when-retrieving-file-contents-via-rest-api/
          T.unsafe(github_client).contents(repo, path: path, ref: commit, accept: "application/vnd.github.v3.raw")
        else
          decode_binary_string(tmp.content)
        end
      rescue Octokit::Forbidden => e
        raise unless e.message.include?("too_large")

        # Fall back to Git Data API to fetch the file
        prefix_dir = directory.gsub(%r{(^/|/$)}, "")
        dir = File.dirname(path).gsub(%r{^/?#{Regexp.escape(prefix_dir)}/?}, "")
        basename = File.basename(path)
        file_details = repo_contents(dir: dir).find { |f| f.name == basename }
        raise unless file_details

        tmp = T.unsafe(github_client).blob(repo, file_details.sha)
        return tmp.content if tmp.encoding == "utf-8"

        decode_binary_string(tmp.content)
      end
      # rubocop:enable Metrics/AbcSize

      # Update the @linked_paths hash by exploiting a side-effect of
      # recursively calling `repo_contents` for each directory up the tree
      # until a submodule or symlink is found
      sig { params(path: String).returns(T.nilable(T::Array[T.untyped])) }
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

      sig { params(path: String).returns(T.nilable(String)) }
      def _linked_dir_for(path)
        linked_dirs = @linked_paths.keys
        linked_dirs
          .select { |k| path.match?(%r{^#{Regexp.quote(k)}(/|$)}) }
          .max_by(&:length)
      end

      # rubocop:disable Metrics/AbcSize
      # rubocop:disable Metrics/MethodLength
      # rubocop:disable Metrics/PerceivedComplexity
      # rubocop:disable Metrics/BlockLength
      sig { params(target_directory: T.nilable(String)).returns(String) }
      def _clone_repo_contents(target_directory:)
        SharedHelpers.with_git_configured(credentials: credentials) do
          path = target_directory || File.join("tmp", source.repo)
          # Assume we're retrying the same branch, or that a `target_directory`
          # is specified when retrying a different branch.
          return path if Dir.exist?(File.join(path, ".git"))

          FileUtils.mkdir_p(path)

          clone_options = StringIO.new
          clone_options << "--no-tags --depth 1"
          clone_options << " --recurse-submodules --shallow-submodules"
          clone_options << " --branch #{source.branch} --single-branch" if source.branch

          submodule_cloning_failed = false
          retries = 0
          begin
            SharedHelpers.run_shell_command(
              <<~CMD
                git clone #{clone_options.string} #{source.url} #{path}
              CMD
            )

            @submodules = find_submodules(path)
          rescue SharedHelpers::HelperSubprocessFailed => e
            if GIT_RETRYABLE_ERRORS.any? { |error| error.match?(e.message) } && retries < 5
              retries += 1
              # 3, 6, 12, 24, 48, ...
              sleep_seconds = (2 ^ (retries - 1)) * 3
              Dependabot.logger.warn(
                "Failed to clone repo #{source.url} due to #{e.message}. Retrying in #{sleep_seconds} seconds..."
              )
              sleep(sleep_seconds)
              retry
            end
            raise unless e.message.match(GIT_SUBMODULE_ERROR_REGEX) && e.message.downcase.include?("submodule")

            submodule_cloning_failed = true
            match = T.must(e.message.match(GIT_SUBMODULE_ERROR_REGEX))
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
              fetch_options << if submodule_cloning_failed
                                 " --no-recurse-submodules"
                               else
                                 " --recurse-submodules=on-demand"
                               end
              # Need to fetch the commit due to the --depth 1 above.
              if is_lfs_enabled(path.to_s)
                SharedHelpers.run_shell_command("git lfs install")
                SharedHelpers.run_shell_command("git-lfs-fetch #{fetch_options.string} origin #{source.commit}")
              else
                SharedHelpers.run_shell_command("git fetch #{fetch_options.string} origin #{source.commit}")
              end
              reset_options = StringIO.new
              reset_options << "--hard"
              reset_options << if submodule_cloning_failed
                                 " --no-recurse-submodules"
                               else
                                 " --recurse-submodules"
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

      sig { params(str: String).returns(String) }
      def decode_binary_string(str)
        bom = (+"\xEF\xBB\xBF").force_encoding(Encoding::BINARY)
        Base64.decode64(str).delete_prefix(bom).force_encoding("UTF-8").encode
      end

      sig { params(path: String).returns(T::Array[String]) }
      def find_submodules(path)
        lfs_enabled = is_lfs_enabled(path) if lfs_enabled.nil?
        SharedHelpers.run_shell_command("git-lfs-checkout") if lfs_enabled
        command_string = get_command_string(path, lfs_enabled)
        #  eep command_string
        SharedHelpers.run_shell_command(command_string).split("\n").filter_map do |line|
          info = line.split

          type = info.first
          path = T.must(info.last)
          next path if type == DependencyFile::Mode::SUBMODULE
        end
      rescue SharedHelpers::HelperSubprocessFailed => e
        Dependabot.logger.warn("LFS is enabled in this repo.  Please use an LFS enabled client") if lfs_enabled
        Dependabot.logger.error(e.message)
        raise e.exception("Message: #{error.message}")
      end

      sig { params(path: String).returns(T.nilable(T::Boolean)) }
      def is_lfs_enabled(path)
        filepath = File.join(path, ".gitattributes")
        lfs_enabled = T.let(true, T::Boolean) if File.exist?(filepath) && File.readable?(filepath)
          && SharedHelpers.run_shell_command("cat #{filepath} | grep \"filter=lfs\"").include?("filter=lfs")
      rescue Exception => e
        # this should not be needed, but I don't trust 'should'
        lfs_enabled = T.let(false, T::Boolean)
        raise e
      end

      sig { params(path: String, lfs_enabled: T.nilable(T::Boolean)).returns(String) }
      def get_command_string(path, lfs_enabled)
        return "git -C #{path} ls-files --stage" unless lfs_enabled
        Dependabot.logger.warn("LFS is enabled in this repo.  Please use an LFS enabled client")
        command_string = "cd #{path};git-lfs ls-files --stage"
        return command_string
      end
    end
  end
end
# rubocop:enable Metrics/ClassLength
