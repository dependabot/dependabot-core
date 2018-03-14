# frozen_string_literal: true

module Dependabot
  module MetadataFinders
    class Base
      require "dependabot/metadata_finders/base/changelog_finder"
      require "dependabot/metadata_finders/base/release_finder"
      require "dependabot/metadata_finders/base/commits_finder"

      class Source
        SOURCE_REGEX = %r{
          (?<host>github(?=\.com)|bitbucket(?=\.org)|gitlab(?=\.com))
          (?:\.com|\.org)[/:]
          (?<repo>[^/\s]+/(?:(?!\.git)[^/\s#])+)[\./]?
          (?:(?:tree|blob|src)/master/(?<directory>.*)[\#|/])?
        }x

        attr_reader :host, :repo, :directory

        def self.from_url(url_string)
          return unless url_string&.match?(SOURCE_REGEX)

          captures = url_string.match(SOURCE_REGEX).named_captures

          new(
            host: captures.fetch("host"),
            repo: captures.fetch("repo"),
            directory: captures.fetch("directory")
          )
        end

        def initialize(host:, repo:, directory: nil)
          @host = host
          @repo = repo
          @directory = directory
        end

        def url
          case host
          when "github" then "https://github.com/" + repo
          when "bitbucket" then "https://bitbucket.org/" + repo
          when "gitlab" then "https://gitlab.com/" + repo
          else raise "Unexpected repo host '#{host}'"
          end
        end
      end

      attr_reader :dependency, :credentials

      def initialize(dependency:, credentials:)
        @dependency = dependency
        @credentials = credentials
      end

      def source_url
        source&.url
      end

      def homepage_url
        source_url
      end

      def changelog_url
        @changelog_finder ||= ChangelogFinder.new(
          dependency: dependency,
          source: source,
          credentials: credentials
        )
        @changelog_finder.changelog_url
      end

      def changelog_text
        @changelog_finder ||= ChangelogFinder.new(
          dependency: dependency,
          source: source,
          credentials: credentials
        )
        @changelog_finder.changelog_text
      end

      def upgrade_guide_url
        @changelog_finder ||= ChangelogFinder.new(
          dependency: dependency,
          source: source,
          credentials: credentials
        )
        @changelog_finder.upgrade_guide_url
      end

      def upgrade_guide_text
        @changelog_finder ||= ChangelogFinder.new(
          dependency: dependency,
          source: source,
          credentials: credentials
        )
        @changelog_finder.upgrade_guide_text
      end

      def releases_url
        @release_finder ||= ReleaseFinder.new(
          dependency: dependency,
          source: source,
          credentials: credentials
        )
        @release_finder.releases_url
      end

      def releases_text
        @release_finder ||= ReleaseFinder.new(
          dependency: dependency,
          source: source,
          credentials: credentials
        )
        @release_finder.releases_text
      end

      def commits_url
        @commits_finder ||= CommitsFinder.new(
          dependency: dependency,
          source: source,
          credentials: credentials
        )
        @commits_finder.commits_url
      end

      def commits
        @commits_finder ||= CommitsFinder.new(
          dependency: dependency,
          source: source,
          credentials: credentials
        )
        @commits_finder.commits
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
