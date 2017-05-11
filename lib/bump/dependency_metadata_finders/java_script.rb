# frozen_string_literal: true
require "excon"
require "bump/dependency_metadata_finders/base"
require "bump/shared_helpers"

module Bump
  module DependencyMetadataFinders
    class JavaScript < Base
      private

      def look_up_github_repo
        return @github_repo if @github_repo_lookup_attempted
        @github_repo_lookup_attempted = true

        npm_url = "http://registry.npmjs.org/#{dependency.name}"
        npm_response =
          Excon.get(npm_url, middlewares: SharedHelpers.excon_middleware)

        all_versions =
          JSON.parse(npm_response.body)["versions"].
          sort_by { |version, _| Gem::Version.new(version) }.
          reverse

        potential_source_urls =
          all_versions.map { |_, v| get_url(v.fetch("repository", {})) } +
          all_versions.map { |_, v| v["homepage"] } +
          all_versions.map { |_, v| get_url(v.fetch("bugs", {})) }

        potential_source_urls = potential_source_urls.compact

        source_url = potential_source_urls.find { |url| url =~ GITHUB_REGEX }

        @github_repo = source_url.match(GITHUB_REGEX)[:repo] if source_url
      end

      def get_url(details)
        case details
        when String then details
        when Hash then details.fetch("url", nil)
        end
      end
    end
  end
end
