# frozen_string_literal: true
require "gems"
require "excon"
require "bump/dependency_metadata_finders/base"

module Bump
  module DependencyMetadataFinders
    class Python < Base
      private

      def look_up_github_repo
        return @github_repo if @github_repo_lookup_attempted
        @github_repo_lookup_attempted = true
        pypi_url = "https://pypi.python.org/pypi/#{dependency.name}/json"
        package = JSON.parse(Excon.get(pypi_url).body)

        all_versions = package.fetch("releases", {}).values
        info = package.fetch("info", {})

        potential_source_urls =
          all_versions.map { |v| !v[0].nil? && v[0].fetch("url", {}) } +
          [info.fetch("home_page", {})]

        potential_source_urls = potential_source_urls.reject(&:nil?)

        source_url = potential_source_urls.find { |url| url =~ GITHUB_REGEX }

        @github_repo =
          source_url.nil? ? nil : source_url.match(GITHUB_REGEX)[:repo]
      end
    end
  end
end
