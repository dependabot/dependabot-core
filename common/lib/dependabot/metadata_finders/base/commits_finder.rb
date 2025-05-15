# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/clients/github_with_retries"
require "dependabot/clients/gitlab_with_retries"
require "dependabot/clients/bitbucket_with_retries"
require "dependabot/shared_helpers"
require "dependabot/git_metadata_fetcher"
require "dependabot/git_commit_checker"
require "dependabot/metadata_finders/base"
require "dependabot/credential"

module Dependabot
  module MetadataFinders
    class Base
      class CommitsFinder
        extend T::Sig

        sig { returns(T.nilable(Dependabot::Source)) }
        attr_reader :source

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig do
          params(
            source: T.nilable(Dependabot::Source),
            dependency: Dependabot::Dependency,
            credentials: T::Array[Dependabot::Credential]
          )
            .void
        end
        def initialize(source:, dependency:, credentials:)
          @source = source
          @dependency = dependency
          @credentials = credentials
        end

        sig { returns(T.nilable(String)) }
        def commits_url
          return unless source
          return if T.must(source).provider == "codecommit" # TODO: Fetch Codecommit commits

          path =
            case T.must(source).provider
            when "github" then github_compare_path(new_tag, previous_tag)
            when "bitbucket" then bitbucket_compare_path(new_tag, previous_tag)
            when "gitlab" then gitlab_compare_path(new_tag, previous_tag)
            when "azure" then azure_compare_path(new_tag, previous_tag)
            when "example" then ""
            else raise "Unexpected source provider '#{T.must(source).provider}'"
            end

          "#{T.must(source).url}/#{path}"
        end

        sig { returns(T::Array[T::Hash[Symbol, String]]) }
        def commits
          return [] unless source
          return [] unless new_tag && previous_tag

          case T.must(source).provider
          when "github" then fetch_github_commits
          when "bitbucket" then fetch_bitbucket_commits
          when "gitlab" then fetch_gitlab_commits
          when "azure" then fetch_azure_commits
          when "codecommit" then [] # TODO: Fetch Codecommit commits
          else raise "Unexpected source provider '#{T.must(source).provider}'"
          end
        end

        sig { returns(T.nilable(String)) }
        def new_tag
          new_version = dependency.version

          return T.must(new_version) if git_source?(dependency.requirements) && git_sha?(new_version)

          return new_ref if new_ref && ref_changed?

          tags = dependency_tags
                 .select { |tag| tag_matches_version?(tag, new_version) }
                 .sort_by(&:length)

          tags.find { |t| t.include?(dependency.name) } || tags.first
        end

        private

        # rubocop:disable Metrics/PerceivedComplexity
        sig { returns(T.nilable(String)) }
        def previous_tag
          previous_version = dependency.previous_version

          if git_source?(dependency.previous_requirements) &&
             git_sha?(previous_version)
            previous_version
          elsif previous_ref && ref_changed?
            previous_ref
          elsif previous_version
            tags = dependency_tags
                   .select { |tag| tag_matches_version?(tag, previous_version) }
                   .sort_by(&:length)

            tags.find { |t| t.include?(dependency.name) } || tags.first
          elsif !git_source?(dependency.previous_requirements)
            lowest_tag_satisfying_previous_requirements
          end
        end

        # rubocop:enable Metrics/PerceivedComplexity

        sig { returns(String) }
        def lowest_tag_satisfying_previous_requirements
          tags = dependency_tags
                 .select { |t| version_from_tag(t) }
                 .select { |t| satisfies_previous_reqs?(version_from_tag(t)) }
                 .sort_by { |t| [version_from_tag(t), t.length] }

          tags.find { |t| t.include?(dependency.name) } || T.must(tags.first)
        end

        sig { params(tag: String).returns(T.nilable(Dependabot::Version)) }
        def version_from_tag(tag)
          version_class.new(tag.gsub(/^v/, "")) if version_class.correct?(tag.gsub(/^v/, ""))

          return unless tag.gsub(/^[^\d]*/, "").length > 1
          return unless version_class.correct?(tag.gsub(/^[^\d]*/, ""))

          version_class.new(tag.gsub(/^[^\d]*/, ""))
        end

        sig { params(version: T.nilable(Dependabot::Version)).returns(T::Boolean) }
        def satisfies_previous_reqs?(version)
          T.must(dependency.previous_requirements).all? do |req|
            next true unless req.fetch(:requirement)

            requirement_class
              .requirements_array(req.fetch(:requirement))
              .all? { |r| r.satisfied_by?(version) }
          end
        end

        # TODO: Refactor me so that Composer doesn't need to be special cased
        sig { params(requirements: T.nilable(T::Array[T::Hash[Symbol, T.untyped]])).returns(T::Boolean) }
        def git_source?(requirements)
          # Special case Composer, which uses git as a source but handles tags
          # internally
          return false if dependency.package_manager == "composer"

          sources = requirements&.map { |r| r.fetch(:source) }&.uniq&.compact
          return false if sources.nil? || sources.empty?

          sources.all? { |s| s[:type] == "git" || s["type"] == "git" }
        end

        sig { returns(T::Boolean) }
        def ref_changed?
          # We could go from multiple previous refs (nil) to a single new ref
          previous_ref != new_ref
        end

        sig { returns(T.nilable(String)) }
        def previous_ref
          return unless git_source?(dependency.previous_requirements)

          previous_refs = T.must(dependency.previous_requirements).filter_map do |r|
            r.dig(:source, "ref") || r.dig(:source, :ref)
          end.uniq
          previous_refs.first if previous_refs.count == 1
        end

        sig { returns(T.nilable(String)) }
        def new_ref
          return unless git_source?(dependency.previous_requirements)

          new_refs = dependency.requirements.filter_map do |r|
            r.dig(:source, "ref") || r.dig(:source, :ref)
          end.uniq
          new_refs.first if new_refs.count == 1
        end

        sig { params(tag: String, version: T.nilable(String)).returns(T::Boolean) }
        def tag_matches_version?(tag, version)
          return false unless version

          return tag.match?(/(?:[^0-9\.]|\A)#{Regexp.escape(version)}\z/) unless version_class.correct?(version)

          version_regex = GitCommitChecker::VERSION_REGEX
          return false unless tag.match?(version_regex)

          tag_version = tag.match(version_regex)&.named_captures&.fetch("version")
          return false unless version_class.correct?(tag_version)

          version_class.new(tag_version) == version_class.new(version)
        end

        sig { returns(T::Array[String]) }
        def dependency_tags
          @dependency_tags ||=
            T.let(
              fetch_dependency_tags,
              T.nilable(T::Array[String])
            )
        end

        sig { returns(T::Array[String]) }
        def fetch_dependency_tags
          return [] unless source

          GitMetadataFetcher
            .new(url: T.must(source).url, credentials: credentials)
            .tags
            .map(&:name)
        rescue Dependabot::GitDependenciesNotReachable,
               Octokit::ServiceUnavailable
          # ServiceUnavailable normally means a DMCA takedown
          []
        end

        sig { params(new_tag: T.nilable(String), previous_tag: T.nilable(String)).returns(String) }
        def github_compare_path(new_tag, previous_tag)
          if part_of_monorepo?
            # If part of a monorepo then we're better off linking to the commits
            # for that directory than trying to put together a compare URL
            Pathname
              .new(File.join("commits/#{new_tag || 'HEAD'}", T.must(source).directory))
              .cleanpath.to_path
          elsif new_tag && previous_tag
            "compare/#{previous_tag}...#{new_tag}"
          else
            new_tag ? "commits/#{new_tag}" : "commits"
          end
        end

        sig { params(new_tag: T.nilable(String), previous_tag: T.nilable(String)).returns(String) }
        def bitbucket_compare_path(new_tag, previous_tag)
          if new_tag && previous_tag
            "branches/compare/#{new_tag}..#{previous_tag}"
          elsif new_tag
            "commits/tag/#{new_tag}"
          else
            "commits"
          end
        end

        sig { params(new_tag: T.nilable(String), previous_tag: T.nilable(String)).returns(String) }
        def gitlab_compare_path(new_tag, previous_tag)
          if new_tag && previous_tag
            "compare/#{previous_tag}...#{new_tag}"
          elsif new_tag
            "commits/#{new_tag}"
          else
            "commits/#{default_gitlab_branch}"
          end
        end

        sig { params(new_tag: T.nilable(String), previous_tag: T.nilable(String)).returns(String) }
        def azure_compare_path(new_tag, previous_tag)
          # GC for commits, GT for tags, and GB for branches
          type = git_sha?(new_tag) ? "GC" : "GT"
          if new_tag && previous_tag
            "branchCompare?baseVersion=#{type}#{previous_tag}&targetVersion=#{type}#{new_tag}"
          elsif new_tag
            "commits?itemVersion=#{type}#{new_tag}"
          else
            "commits"
          end
        end

        sig { returns(T::Array[T::Hash[Symbol, String]]) }
        def fetch_github_commits
          commits =
            begin
              # If part of a monorepo we make two requests in order to get only
              # the commits relevant to the given path
              path = T.must(source).directory&.gsub(%r{^[./]+}, "")
              repo = T.must(source).repo

              args = { sha: previous_tag, path: path }.compact
              previous_commit_shas =
                T.unsafe(github_client).commits(repo, **args).map(&:sha)

              # NOTE: We reverse this so it's consistent with the array we get
              # from `github_client.compare(...)`
              args = { sha: new_tag, path: path }.compact
              T.unsafe(github_client)
               .commits(repo, **args)
               .reject { |c| previous_commit_shas.include?(c.sha) }.reverse
            end
          return [] unless commits

          commits.map do |commit|
            {
              message: commit.commit.message,
              sha: commit.sha,
              html_url: commit.html_url
            }
          end
        rescue Octokit::NotFound
          []
        end

        sig { returns(T::Array[T::Hash[Symbol, String]]) }
        def fetch_bitbucket_commits
          T.unsafe(bitbucket_client)
           .compare(T.must(source).repo, previous_tag, new_tag)
           .map do |commit|
            {
              message: commit.dig("summary", "raw"),
              sha: commit["hash"],
              html_url: commit.dig("links", "html", "href")
            }
          end
        rescue Dependabot::Clients::Bitbucket::NotFound,
               Dependabot::Clients::Bitbucket::Unauthorized,
               Dependabot::Clients::Bitbucket::Forbidden,
               Excon::Error::Server,
               Excon::Error::Socket,
               Excon::Error::Timeout
          []
        end

        sig { returns(T::Array[T::Hash[Symbol, String]]) }
        def fetch_gitlab_commits
          T.unsafe(gitlab_client)
           .compare(T.must(source).repo, previous_tag, new_tag)
           .commits
           .map do |commit|
            {
              message: commit["message"],
              sha: commit["id"],
              html_url: "#{T.must(source).url}/commit/#{commit['id']}"
            }
          end
        rescue Gitlab::Error::NotFound
          []
        end

        sig { returns(T::Array[T::Hash[Symbol, String]]) }
        def fetch_azure_commits
          type = git_sha?(new_tag) ? "commit" : "tag"
          azure_client
            .compare(previous_tag, new_tag, type)
            .map do |commit|
            {
              message: commit["comment"],
              sha: commit["commitId"],
              html_url: commit["remoteUrl"]
            }
          end
        rescue Dependabot::Clients::Azure::NotFound,
               Dependabot::Clients::Azure::Unauthorized,
               Dependabot::Clients::Azure::Forbidden,
               Excon::Error::Server,
               Excon::Error::Socket,
               Excon::Error::Timeout
          []
        end

        sig { returns(Dependabot::Clients::GitlabWithRetries) }
        def gitlab_client
          @gitlab_client ||=
            T.let(
              Dependabot::Clients::GitlabWithRetries.for_gitlab_dot_com(credentials: credentials),
              T.nilable(Dependabot::Clients::GitlabWithRetries)
            )
        end

        sig { returns(Dependabot::Clients::GithubWithRetries) }
        def github_client
          @github_client ||=
            T.let(
              Dependabot::Clients::GithubWithRetries.for_source(source: T.must(source), credentials: credentials),
              T.nilable(Dependabot::Clients::GithubWithRetries)
            )
        end

        sig { returns(Dependabot::Clients::Azure) }
        def azure_client
          @azure_client ||=
            T.let(
              Dependabot::Clients::Azure.for_source(source: T.must(source), credentials: credentials),
              T.nilable(Dependabot::Clients::Azure)
            )
        end

        sig { returns(Dependabot::Clients::BitbucketWithRetries) }
        def bitbucket_client
          @bitbucket_client ||=
            T.let(
              Dependabot::Clients::BitbucketWithRetries.for_bitbucket_dot_org(credentials: credentials),
              T.nilable(Dependabot::Clients::BitbucketWithRetries)
            )
        end

        sig { returns(T::Boolean) }
        def part_of_monorepo?
          return false unless reliable_source_directory?

          ![nil, ".", "/"].include?(T.must(source).directory)
        end

        sig { returns(T.class_of(Dependabot::Version)) }
        def version_class
          dependency.version_class
        end

        sig { returns(T.class_of(Dependabot::Requirement)) }
        def requirement_class
          dependency.requirement_class
        end

        sig { params(version: T.nilable(String)).returns(T::Boolean) }
        def git_sha?(version)
          return false unless version

          version.match?(/^[0-9a-f]{40}$/)
        end

        sig { returns(T::Boolean) }
        def reliable_source_directory?
          MetadataFinders::Base::PACKAGE_MANAGERS_WITH_RELIABLE_DIRECTORIES
            .include?(dependency.package_manager)
        end

        sig { returns(String) }
        def default_gitlab_branch
          @default_gitlab_branch ||=
            T.let(
              gitlab_client.fetch_default_branch(T.must(source).repo),
              T.nilable(String)
            )
        end
      end
    end
  end
end
