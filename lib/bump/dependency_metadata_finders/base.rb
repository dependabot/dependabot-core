# frozen_string_literal: true
module Bump
  module DependencyMetadataFinders
    class Base
      GITHUB_REGEX = %r{github\.com/(?<repo>[^/]+/(?:(?!\.git)[^/])+)[\./]?}
      CHANGELOG_NAMES = %w(changelog history news changes).freeze
      TAG_PREFIX      = /^v/

      attr_reader :dependency, :github_client

      def initialize(dependency:, github_client:)
        @dependency = dependency
        @github_client = github_client
      end

      def github_repo
        return @github_repo if @github_repo_lookup_attempted
        look_up_github_repo
      end

      def github_repo_url
        return unless github_repo
        github_client.web_endpoint + github_repo
      end

      def github_compare_url
        return unless github_repo

        @tags ||= look_up_repo_tags

        previous_version = dependency.previous_version
        version = dependency.version
        if @tags.include?(previous_version) && @tags.include?(version)
          "#{github_repo_url}/compare/v#{previous_version}...v#{version}"
        elsif @tags.include?(version)
          "#{github_repo_url}/commits/v#{version}"
        else
          "#{github_repo_url}/commits"
        end
      end

      def changelog_url
        return unless github_repo
        return @changelog_url if @changelog_url_lookup_attempted

        look_up_changelog_url
      end

      private

      def look_up_changelog_url
        @changelog_url_lookup_attempted = true

        files = github_client.contents(github_repo)
        file = files.find { |f| CHANGELOG_NAMES.any? { |w| f.name =~ /#{w}/i } }

        @changelog_url = file.nil? ? nil : file.html_url
      rescue Octokit::NotFound
        @changelog_url = nil
      end

      def look_up_repo_tags
        github_client.tags(github_repo).map do |tag|
          tag["name"].to_s.gsub(TAG_PREFIX, "")
        end
      rescue Octokit::NotFound
        []
      end

      def look_up_github_repo
        raise NotImplementedError
      end
    end
  end
end
