# frozen_string_literal: true

require "dependabot/source"

module Dependabot
  module MetadataFinders
    class Base
      require "dependabot/metadata_finders/base/changelog_finder"
      require "dependabot/metadata_finders/base/release_finder"
      require "dependabot/metadata_finders/base/commits_finder"

      PACKAGE_MANAGERS_WITH_RELIABLE_DIRECTORIES = %w(npm_and_yarn pub).freeze

      attr_reader :dependency, :credentials

      def initialize(dependency:, credentials:)
        @dependency = dependency
        @credentials = credentials
      end

      def source_url
        if reliable_source_directory?
          source&.url_with_directory
        else
          source&.url
        end
      end

      def homepage_url
        source_url
      end

      def changelog_url
        @changelog_finder ||= ChangelogFinder.new(
          dependency: dependency,
          source: source,
          credentials: credentials,
          suggested_changelog_url: suggested_changelog_url
        )
        @changelog_finder.changelog_url
      end

      def changelog_text
        @changelog_finder ||= ChangelogFinder.new(
          dependency: dependency,
          source: source,
          credentials: credentials,
          suggested_changelog_url: suggested_changelog_url
        )
        @changelog_finder.changelog_text
      end

      def upgrade_guide_url
        @changelog_finder ||= ChangelogFinder.new(
          dependency: dependency,
          source: source,
          credentials: credentials,
          suggested_changelog_url: suggested_changelog_url
        )
        @changelog_finder.upgrade_guide_url
      end

      def upgrade_guide_text
        @changelog_finder ||= ChangelogFinder.new(
          dependency: dependency,
          source: source,
          credentials: credentials,
          suggested_changelog_url: suggested_changelog_url
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

      def maintainer_changes
        nil
      end

      private

      def suggested_changelog_url
        nil
      end

      def source
        return @source if @source_lookup_attempted

        @source_lookup_attempted = true
        @source = look_up_source
      end

      def look_up_source
        raise NotImplementedError
      end

      def reliable_source_directory?
        MetadataFinders::Base::PACKAGE_MANAGERS_WITH_RELIABLE_DIRECTORIES.
          include?(dependency.package_manager)
      end
    end
  end
end
