# frozen_string_literal: true
module Dependabot
  module MetadataFinders
    class Base
      GITHUB_REGEX = %r{github\.com/(?<repo>[^/]+/(?:(?!\.git)[^/])+)[\./]?}
      CHANGELOG_NAMES = %w(changelog history news changes).freeze

      attr_reader :dependency, :github_client

      def initialize(dependency:, github_client:)
        @dependency = dependency
        @github_client = github_client
      end

      def github_repo
        return @github_repo if @github_repo_lookup_attempted
        @github_repo_lookup_attempted = true
        @github_repo = look_up_github_repo
      end

      def github_repo_url
        return unless github_repo
        github_client.web_endpoint + github_repo
      end

      def github_compare_url
        return unless github_repo

        @tags ||= look_up_repo_tags

        current_version = dependency.version
        previous_version = dependency.previous_version
        current_tag = @tags.find { |t| t =~ version_regex(current_version) }
        previous_tag = @tags.find { |t| t =~ version_regex(previous_version) }

        if current_tag && previous_tag
          "#{github_repo_url}/compare/#{previous_tag}...#{current_tag}"
        elsif current_tag
          "#{github_repo_url}/commits/#{current_tag}"
        else
          "#{github_repo_url}/commits"
        end
      end

      def changelog_url
        return unless github_repo
        return @changelog_url if @changelog_url_lookup_attempted

        look_up_changelog_url
      end

      def release_url
        return unless github_repo
        return @release_url if @release_url_lookup_attempted

        look_up_release_url
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

      def look_up_release_url
        @release_url_lookup_attempted = true

        release_regex = version_regex(dependency.version)
        release = github_client.releases(github_repo).find do |r|
          r.name.to_s =~ release_regex || r.tag_name.to_s =~ release_regex
        end

        @release_url = release&.html_url
      rescue Octokit::NotFound
        @release_url = nil
      end

      def look_up_repo_tags
        github_client.tags(github_repo).map { |tag| tag["name"] }
      rescue Octokit::NotFound
        []
      end

      def look_up_github_repo
        raise NotImplementedError
      end

      def version_regex(version)
        /[^0-9\.]#{Regexp.escape(version)}\z/
      end
    end
  end
end
