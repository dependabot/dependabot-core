# frozen_string_literal: true

require "dependabot/clients/github_with_retries"
require "dependabot/clients/gitlab"
require "dependabot/clients/bitbucket"
require "dependabot/shared_helpers"
require "dependabot/metadata_finders/base"

module Dependabot
  module MetadataFinders
    class Base
      class CommitsFinder
        PACKAGE_MANAGERS_WITH_RELIABLE_DIRS = %w(
          npm_and_yarn
        ).freeze

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

          if git_source?(dependency.requirements) then new_version
          else
            tags = dependency_tags.
                   select { |t| t =~ version_regex(new_version) }
            tags.find { |t| t.include?(dependency.name) } || tags.first
          end
        end

        private

        def previous_tag
          previous_version = dependency.previous_version

          if git_source?(dependency.previous_requirements)
            previous_version || previous_ref
          elsif previous_version
            tags = dependency_tags.
                   select { |t| t =~ version_regex(previous_version) }
            tags.find { |t| t.include?(dependency.name) } || tags.first
          else
            lowest_tag_satisfying_previous_requirements
          end
        end

        def lowest_tag_satisfying_previous_requirements
          tags = dependency_tags.
                 select { |t| version_class.correct?(t.gsub(/^v/, "")) }.
                 select do |t|
                   version = version_class.new(t.gsub(/^v/, ""))
                   dependency.previous_requirements.all? do |req|
                     next true unless req.fetch(:requirement)

                     requirement_class.
                       requirements_array(req.fetch(:requirement)).
                       all? { |r| r.satisfied_by?(version) }
                   end
                 end

          tags.min_by { |t| version_class.new(t.gsub(/^v/, "")) }
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

        def previous_ref
          return unless git_source?(dependency.previous_requirements)

          dependency.previous_requirements.map do |r|
            r.dig(:source, "ref") || r.dig(:source, :ref)
          end.compact.first
        end

        def version_regex(version)
          /(?:[^0-9\.]|\A)#{Regexp.escape(version || "unknown")}\z/
        end

        def dependency_tags
          @dependency_tags ||= fetch_dependency_tags
        end

        def fetch_dependency_tags
          return [] unless source

          case source.provider
          when "github"
            github_client.tags(source.repo, per_page: 100).map(&:name)
          when "bitbucket"
            bitbucket_client.tags(source.repo).map { |tag| tag["name"] }
          when "gitlab"
            gitlab_client.tags(source.repo).map(&:name)
          when "azure"
            [] # TODO: Fetch Azure tags
          else raise "Unexpected source provider '#{source.provider}'"
          end
        rescue Octokit::NotFound, Gitlab::Error::NotFound,
               Dependabot::Clients::Bitbucket::NotFound,
               Dependabot::Clients::Bitbucket::Unauthorized,
               Dependabot::Clients::Bitbucket::Forbidden
          []
        end

        def github_compare_path(new_tag, previous_tag)
          if new_tag && previous_tag
            return "compare/#{previous_tag}...#{new_tag}"
          end

          unless reliable_source_directory? &&
                 ![nil, ".", "/"].include?(source.directory)
            return new_tag ? "commits/#{new_tag}" : "commits"
          end

          Pathname.
            new(File.join("commits/#{new_tag || 'HEAD'}", source.directory)).
            cleanpath.to_path
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
            github_client.compare(source.repo, previous_tag, new_tag).commits
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
               Dependabot::Clients::Bitbucket::Forbidden
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
          @gitlab_client ||= Dependabot::Clients::Gitlab.
                             for_gitlab_dot_com(credentials: credentials)
        end

        def github_client
          @github_client ||= Dependabot::Clients::GithubWithRetries.
                             for_github_dot_com(credentials: credentials)
        end

        def bitbucket_client
          @bitbucket_client ||= Dependabot::Clients::Bitbucket.
                                for_bitbucket_dot_org(credentials: credentials)
        end

        def version_class
          Utils.version_class_for_package_manager(dependency.package_manager)
        end

        def requirement_class
          Utils.requirement_class_for_package_manager(
            dependency.package_manager
          )
        end

        def reliable_source_directory?
          PACKAGE_MANAGERS_WITH_RELIABLE_DIRS.
            include?(dependency.package_manager)
        end
      end
    end
  end
end
