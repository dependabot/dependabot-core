# frozen_string_literal: true
require "gems"
require "bump/dependency_metadata_finders/base"

module Bump
  module DependencyMetadataFinders
    class Ruby < Base
      SOURCE_KEYS = %w(
        source_code_uri
        homepage_uri
        wiki_uri
        bug_tracker_uri
        documentation_uri
      ).freeze

      private

      def look_up_github_repo
        source_url = Gems.
                     info(dependency.name).
                     values_at(*SOURCE_KEYS).
                     compact.
                     find { |url| url =~ GITHUB_REGEX }

        source_url.match(GITHUB_REGEX)[:repo] if source_url
      rescue JSON::ParserError
        # Replace with Gems::NotFound error if/when
        # https://github.com/rubygems/gems/pull/38 is merged.
        nil
      end
    end
  end
end
