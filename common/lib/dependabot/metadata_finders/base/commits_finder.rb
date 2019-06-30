# frozen_string_literal: true

require "dependabot/clients/github_with_retries"
require "dependabot/clients/gitlab_with_retries"
require "dependabot/clients/bitbucket_with_retries"
require "dependabot/shared_helpers"
require "dependabot/git_metadata_fetcher"
require "dependabot/git_commit_checker"
require "dependabot/metadata_finders/base"

module Dependabot
  module MetadataFinders
    class Base
      class CommitsFinder
        attr_reader :source, :dependency, :credentials

        def initialize(source:, dependency:, credentials:)
          @source = source
          @dependency = dependency
          @credentials = credentials
        end

        def commits_url
          return unless source
          return if source.provider == "azure" # TODO: Fetch Azure commits

          path =
            case source.provider
            when "github" then github_compare_path(new_tag, previous_tag)
            when "bitbucket" then bitbucket_compare_path(new_tag, previous_tag)
            when "gitlab" then gitlab_compare_path(new_tag, previous_tag)
            else raise "Unexpected source provider '#{source.provider}'"
            end

          "#{source.url}/#{path}"
        end

        # rubocop:disable Metrics/CyclomaticComplexity
        def commits
          return [] unless source
          return [] unless new_tag && previous_tag

          case source.provider
          when "github" then fetch_github_commits
          when "bitbucket" then fetch_bitbucket_commits
          when "gitlab" then fetch_gitlab_commits
          when "azure" then [] # TODO: Fetch Azure commits
          else raise "Unexpected source provider '#{source.provider}'"
          end
        end
        # rubocop:enable Metrics/CyclomaticComplexity

        def new_tag
          new_version = dependency.version

          if git_source?(dependency.requirements) && git_sha?(new_version)
            return new_version
          end

          return new_ref if git_source?(dependency.requirements) && ref_changed?

          tags = dependency_tags.
                 select { |tag| tag_matches_version?(tag, new_version) }.
                 sort_by(&:length)

          tags.find { |t| t.include?(dependency.name) } || tags.first
        end

        private

        # rubocop:disable Metrics/CyclomaticComplexity
        # rubocop:disable Metrics/PerceivedComplexity
        def previous_tag
          previous_version = dependency.previous_version

          if git_source?(dependency.previous_requirements) &&
             git_sha?(previous_version)
            previous_version
          elsif git_source?(dependency.previous_requirements) && ref_changed?
            previous_ref
          elsif previous_version
            tags = dependency_tags.
                   select { |tag| tag_matches_version?(tag, previous_version) }.
                   sort_by(&:length)

            tags.find { |t| t.include?(dependency.name) } || tags.first
          elsif !git_source?(dependency.previous_requirements)
            lowest_tag_satisfying_previous_requirements
          end
        end
        # rubocop:enable Metrics/CyclomaticComplexity
        # rubocop:enable Metrics/PerceivedComplexity

        def lowest_tag_satisfying_previous_requirements
          tags = dependency_tags.
                 select { |t| version_from_tag(t) }.
                 select { |t| satisfies_previous_reqs?(version_from_tag(t)) }.
                 sort_by { |t| [version_from_tag(t), t.length] }

          tags.find { |t| t.include?(dependency.name) } || tags.first
        end

        def version_from_tag(tag)
          if version_class.correct?(tag.gsub(/^v/, ""))
            version_class.new(tag.gsub(/^v/, ""))
          end

          return unless tag.gsub(/^[^\d]*/, "").length > 1
          return unless version_class.correct?(tag.gsub(/^[^\d]*/, ""))

          version_class.new(tag.gsub(/^[^\d]*/, ""))
        end

        def satisfies_previous_reqs?(version)
          dependency.previous_requirements.all? do |req|
            next true unless req.fetch(:requirement)

            requirement_class.
              requirements_array(req.fetch(:requirement)).
              all? { |r| r.satisfied_by?(version) }
          end
        end

        # TODO: Refactor me so that Composer doesn't need to be special cased
        def git_source?(requirements)
          # Special case Composer, which uses git as a source but handles tags
          # internally
          return false if dependency.package_manager == "composer"

          sources = requirements.map { |r| r.fetch(:source) }.uniq.compact
          return false if sources.empty?
          raise "Multiple sources! #{sources.join(', ')}" if sources.count > 1

          source_type = sources.first[:type] || sources.first.fetch("type")
          source_type == "git"
        end

        def ref_changed?
          return false unless previous_ref && new_ref

          previous_ref != new_ref
        end

        def previous_ref
          return unless git_source?(dependency.previous_requirements)

          dependency.previous_requirements.map do |r|
            r.dig(:source, "ref") || r.dig(:source, :ref)
          end.compact.first
        end

        def new_ref
          return unless git_source?(dependency.previous_requirements)

          dependency.requirements.map do |r|
            r.dig(:source, "ref") || r.dig(:source, :ref)
          end.compact.first
        end

        def tag_matches_version?(tag, version)
          return false unless version

          unless version_class.correct?(version)
            return tag.match?(/(?:[^0-9\.]|\A)#{Regexp.escape(version)}\z/)
          end

          version_regex = GitCommitChecker::VERSION_REGEX
          return false unless tag.match?(version_regex)

          tag_version = tag.match(version_regex).named_captures.fetch("version")
          return false unless version_class.correct?(tag_version)

          version_class.new(tag_version) == version_class.new(version)
        end

        def dependency_tags
          @dependency_tags ||= fetch_dependency_tags
        end

        def fetch_dependency_tags
          return [] unless source

          GitMetadataFetcher.
            new(url: source.url, credentials: credentials).
            tags.
            map(&:name)
        rescue Dependabot::GitDependenciesNotReachable,
               Octokit::ServiceUnavailable
          # ServiceUnavailable normally means a DMCA takedown
          []
        end

        def github_compare_path(new_tag, previous_tag)
          if part_of_monorepo?
            # If part of a monorepo then we're better off linking to the commits
            # for that directory than trying to put together a compare URL
            Pathname.
              new(File.join("commits/#{new_tag || 'HEAD'}", source.directory)).
              cleanpath.to_path
          elsif new_tag && previous_tag
            "compare/#{previous_tag}...#{new_tag}"
          else
            new_tag ? "commits/#{new_tag}" : "commits"
          end
        end

        def bitbucket_compare_path(new_tag, previous_tag)
          if new_tag && previous_tag
            "branches/compare/#{new_tag}..#{previous_tag}"
          elsif new_tag
            "commits/tag/#{new_tag}"
          else
            "commits"
          end
        end

        def gitlab_compare_path(new_tag, previous_tag)
          if new_tag && previous_tag
            "compare/#{previous_tag}...#{new_tag}"
          elsif new_tag
            "commits/#{new_tag}"
          else
            "commits/master"
          end
        end

        def fetch_github_commits
          commits =
            begin
              # If part of a monorepo we make two requests in order to get only
              # the commits relevant to the given path
              path = source.directory&.gsub(%r{^[./]+}, "")
              repo = source.repo

              args = { sha: previous_tag, path: path }.compact
              previous_commit_shas =
                github_client.commits(repo, **args).map(&:sha)

              # Note: We reverse this so it's consistent with the array we get
              # from `github_client.compare(...)`
              args = { sha: new_tag, path: path }.compact
              github_client.
                commits(repo, **args).
                reject { |c| previous_commit_shas.include?(c.sha) }.reverse
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

        def fetch_bitbucket_commits
          bitbucket_client.
            compare(source.repo, previous_tag, new_tag).
            map do |commit|
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

        def fetch_gitlab_commits
          gitlab_client.
            compare(source.repo, previous_tag, new_tag).
            commits.
            map do |commit|
              {
                message: commit["message"],
                sha: commit["id"],
                html_url: "#{source.url}/commit/#{commit['id']}"
              }
            end
        rescue Gitlab::Error::NotFound
          []
        end

        def gitlab_client
          @gitlab_client ||= Dependabot::Clients::GitlabWithRetries.
                             for_gitlab_dot_com(credentials: credentials)
        end

        def github_client
          @github_client ||= Dependabot::Clients::GithubWithRetries.
                             for_github_dot_com(credentials: credentials)
        end

        def bitbucket_client
          @bitbucket_client ||= Dependabot::Clients::BitbucketWithRetries.
                                for_bitbucket_dot_org(credentials: credentials)
        end

        def part_of_monorepo?
          return false unless reliable_source_directory?

          ![nil, ".", "/"].include?(source.directory)
        end

        def version_class
          Utils.version_class_for_package_manager(dependency.package_manager)
        end

        def requirement_class
          Utils.requirement_class_for_package_manager(
            dependency.package_manager
          )
        end

        def git_sha?(version)
          return false unless version

          version.match?(/^[0-9a-f]{40}$/)
        end

        def reliable_source_directory?
          MetadataFinders::Base::PACKAGE_MANAGERS_WITH_RELIABLE_DIRECTORIES.
            include?(dependency.package_manager)
        end
      end
    end
  end
end
