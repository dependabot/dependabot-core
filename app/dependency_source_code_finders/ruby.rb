require "gems"
require "./app/dependency_source_code_finders/base"

module DependencySourceCodeFinders
  class Ruby < Base
    SOURCE_KEYS = %w(source_code_uri homepage_uri wiki_uri bug_tracker_uri
                     documentation_uri).freeze

    private

    def look_up_github_repo
      @github_repo_lookup_attempted = true

      potential_source_urls =
        Gems.info(dependency_name).select do |key, _|
          SOURCE_KEYS.include?(key)
        end.values

      source_url = potential_source_urls.find { |url| url =~ GITHUB_REGEX }

      @github_repo =
        source_url.nil? ? nil : source_url.match(GITHUB_REGEX)[:repo]
    end
  end
end
