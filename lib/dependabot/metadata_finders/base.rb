# frozen_string_literal: true

require "gitlab"
require "octokit"
require "dependabot/shared_helpers"

module Dependabot
  module MetadataFinders
    class Base
      require "dependabot/metadata_finders/base/changelog_finder"
      require "dependabot/metadata_finders/base/release_finder"

      SOURCE_REGEX = %r{
        (?<host>github(?=\.com)|bitbucket(?=\.org)|gitlab(?=\.com))
        (?:\.com|\.org)/
        (?<repo>[^/\s]+/(?:(?!\.git)[^/\s])+)[\./]?
      }x

      attr_reader :dependency, :github_client

      def initialize(dependency:, github_client:)
        @dependency = dependency
        @github_client = github_client
      end

      def source_url
        return unless source

        case source.fetch("host")
        when "github" then github_client.web_endpoint + source.fetch("repo")
        when "bitbucket" then "https://bitbucket.org/" + source.fetch("repo")
        when "gitlab" then "https://gitlab.com/" + source.fetch("repo")
        else raise "Unexpected repo host '#{source.fetch('host')}'"
        end
      end

      def changelog_url
        @changelog_finder ||= ChangelogFinder.new(
          source: source,
          github_client: github_client
        )
        @changelog_finder.changelog_url
      end

      def release_url
        @release_finder ||= ReleaseFinder.new(
          dependency: dependency,
          source: source,
          github_client: github_client
        )
        @release_finder.release_url
      end

      def commits_url
        return @commits_url if @commits_url_lookup_attempted

        @commits_url_lookup_attempted = true
        @commits_url ||= look_up_commits_url
      end

      private

      def source
        return @source if @source_lookup_attempted
        @source_lookup_attempted = true
        @source = look_up_source
      end

      def look_up_source
        raise NotImplementedError
      end

      def look_up_commits_url
        return unless source_url

        tags = fetch_dependency_tags

        current_version = dependency.version
        previous_version = dependency.previous_version
        current_tag = tags.find { |t| t =~ version_regex(current_version) }
        previous_tag = tags.find { |t| t =~ version_regex(previous_version) }

        build_compare_commits_url(current_tag, previous_tag)
      end

      def version_regex(version)
        /(?:[^0-9\.]|\A)#{Regexp.escape(version || "unknown")}\z/
      end

      def fetch_dependency_tags
        return [] unless source

        case source.fetch("host")
        when "github"
          github_client.tags(source["repo"], per_page: 100).map(&:name)
        when "bitbucket"
          fetch_bitbucket_tags
        when "gitlab"
          gitlab_client.tags(source["repo"]).map(&:name)
        else raise "Unexpected repo host '#{source.fetch('host')}'"
        end
      rescue Octokit::NotFound, Gitlab::Error::NotFound
        []
      end

      def build_compare_commits_url(current_tag, previous_tag)
        case source.fetch("host")
        when "github"
          build_github_compare_url(current_tag, previous_tag)
        when "bitbucket"
          build_bitbucket_compare_url(current_tag, previous_tag)
        when "gitlab"
          build_gitlab_compare_url(current_tag, previous_tag)
        else raise "Unexpected repo host '#{source.fetch('host')}'"
        end
      end

      def build_github_compare_url(current_tag, previous_tag)
        if current_tag && previous_tag
          "#{source_url}/compare/#{previous_tag}...#{current_tag}"
        elsif current_tag
          "#{source_url}/commits/#{current_tag}"
        else
          "#{source_url}/commits"
        end
      end

      def build_bitbucket_compare_url(current_tag, previous_tag)
        if current_tag && previous_tag
          "#{source_url}/branches/compare/#{current_tag}..#{previous_tag}"
        elsif current_tag
          "#{source_url}/commits/tag/#{current_tag}"
        else
          "#{source_url}/commits"
        end
      end

      def build_gitlab_compare_url(current_tag, previous_tag)
        if current_tag && previous_tag
          "#{source_url}/compare/#{previous_tag}...#{current_tag}"
        elsif current_tag
          "#{source_url}/commits/#{current_tag}"
        else
          "#{source_url}/commits/master"
        end
      end

      def fetch_bitbucket_tags
        url = "https://api.bitbucket.org/2.0/repositories/"\
              "#{source.fetch('repo')}/refs/tags?pagelen=100"
        response = Excon.get(
          url,
          idempotent: true,
          middlewares: SharedHelpers.excon_middleware
        )
        return [] if response.status >= 300

        JSON.parse(response.body).fetch("values", []).map { |tag| tag["name"] }
      end

      def gitlab_client
        @gitlab_client ||=
          Gitlab.client(
            endpoint: "https://gitlab.com/api/v4",
            private_token: ""
          )
      end
    end
  end
end
