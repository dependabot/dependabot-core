# frozen_string_literal: true
require "gems"
require "./app/dependency_source_code_finders/base"

module DependencySourceCodeFinders
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
      @github_repo_lookup_attempted = true

      source_url = Gems.
                   info(dependency_name).
                   values_at(*SOURCE_KEYS).
                   compact.
                   find { |url| url =~ GITHUB_REGEX }

      @github_repo = source_url.match(GITHUB_REGEX)[:repo] if source_url
    end
  end
end
