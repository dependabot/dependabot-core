# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/source"
require "dependabot/credential"

module Dependabot
  module MetadataFinders
    class Base
      extend T::Sig
      extend T::Helpers

      require "dependabot/metadata_finders/base/changelog_finder"
      require "dependabot/metadata_finders/base/release_finder"
      require "dependabot/metadata_finders/base/commits_finder"

      PACKAGE_MANAGERS_WITH_RELIABLE_DIRECTORIES = T.let(%w(npm_and_yarn pub).freeze, T::Array[String])

      sig { returns(Dependabot::Dependency) }
      attr_reader :dependency

      sig { returns(T::Array[Dependabot::Credential]) }
      attr_reader :credentials

      sig do
        params(
          dependency: Dependabot::Dependency,
          credentials: T::Array[Dependabot::Credential]
        )
          .void
      end
      def initialize(dependency:, credentials:)
        @dependency = dependency
        @credentials = credentials
      end

      sig { returns(T.nilable(String)) }
      def source_url
        if reliable_source_directory?
          source&.url_with_directory
        else
          source&.url
        end
      end

      sig { returns(T.nilable(String)) }
      def homepage_url
        source_url
      end

      sig { returns(T.nilable(String)) }
      def changelog_url
        @changelog_finder ||= T.let(
          ChangelogFinder.new(
            dependency: dependency,
            source: source,
            credentials: credentials,
            suggested_changelog_url: suggested_changelog_url
          ),
          T.nilable(ChangelogFinder)
        )
        @changelog_finder.changelog_url
      end

      sig { returns(T.nilable(String)) }
      def changelog_text
        @changelog_finder ||= T.let(
          ChangelogFinder.new(
            dependency: dependency,
            source: source,
            credentials: credentials,
            suggested_changelog_url: suggested_changelog_url
          ),
          T.nilable(ChangelogFinder)
        )
        @changelog_finder.changelog_text
      end

      sig { returns(T.nilable(String)) }
      def upgrade_guide_url
        @changelog_finder ||= T.let(
          ChangelogFinder.new(
            dependency: dependency,
            source: source,
            credentials: credentials,
            suggested_changelog_url: suggested_changelog_url
          ),
          T.nilable(ChangelogFinder)
        )
        @changelog_finder.upgrade_guide_url
      end

      sig { returns(T.nilable(String)) }
      def upgrade_guide_text
        @changelog_finder ||= T.let(
          ChangelogFinder.new(
            dependency: dependency,
            source: source,
            credentials: credentials,
            suggested_changelog_url: suggested_changelog_url
          ),
          T.nilable(ChangelogFinder)
        )
        @changelog_finder.upgrade_guide_text
      end

      sig { returns(T.nilable(String)) }
      def releases_url
        @release_finder ||= T.let(
          ReleaseFinder.new(
            dependency: dependency,
            source: source,
            credentials: credentials
          ),
          T.nilable(ReleaseFinder)
        )
        @release_finder.releases_url
      end

      sig { returns(T.nilable(String)) }
      def releases_text
        @release_finder ||= T.let(
          ReleaseFinder.new(
            dependency: dependency,
            source: source,
            credentials: credentials
          ),
          T.nilable(ReleaseFinder)
        )
        @release_finder.releases_text
      end

      sig { returns(T.nilable(String)) }
      def commits_url
        @commits_finder ||= T.let(
          CommitsFinder.new(
            dependency: dependency,
            source: source,
            credentials: credentials
          ),
          T.nilable(CommitsFinder)
        )
        @commits_finder.commits_url
      end

      sig { returns(T::Array[T::Hash[Symbol, String]]) }
      def commits
        @commits_finder ||= T.let(
          CommitsFinder.new(
            dependency: dependency,
            source: source,
            credentials: credentials
          ),
          T.nilable(CommitsFinder)
        )
        @commits_finder.commits
      end

      sig { overridable.returns(T.nilable(String)) }
      def maintainer_changes
        nil
      end

      private

      sig { overridable.returns(T.nilable(String)) }
      def suggested_changelog_url
        nil
      end

      sig { returns(T.nilable(Dependabot::Source)) }
      def source
        return @source if defined?(@source)

        @source = T.let(look_up_source, T.nilable(Dependabot::Source))
      end

      sig { overridable.returns(T.nilable(Dependabot::Source)) }
      def look_up_source
        raise NotImplementedError
      end

      sig { returns(T::Boolean) }
      def reliable_source_directory?
        MetadataFinders::Base::PACKAGE_MANAGERS_WITH_RELIABLE_DIRECTORIES
          .include?(dependency.package_manager)
      end
    end
  end
end
