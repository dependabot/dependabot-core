# frozen_string_literal: true

module Dependabot
  module MetadataFinders
    class Base
      require "dependabot/metadata_finders/base/changelog_finder"
      require "dependabot/metadata_finders/base/release_finder"
      require "dependabot/metadata_finders/base/commits_url_finder"

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
          dependency: dependency,
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
        @commits_url_finder ||= CommitsUrlFinder.new(
          dependency: dependency,
          source: source,
          github_client: github_client
        )
        @commits_url_finder.commits_url
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
    end
  end
end
