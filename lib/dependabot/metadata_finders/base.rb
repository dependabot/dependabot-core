# frozen_string_literal: true
require "gitlab"
require "octokit"
require "dependabot/shared_helpers"

module Dependabot
  module MetadataFinders
    class Base
      SOURCE_REGEX = %r{
        (?<host>github(?=\.com)|bitbucket(?=\.org)|gitlab(?=\.com))
        (?:\.com|\.org)/
        (?<repo>[^/]+/(?:(?!\.git)[^/])+)[\./]?
      }x
      CHANGELOG_NAMES = %w(changelog history news changes).freeze

      attr_reader :dependency, :github_client

      def initialize(dependency:, github_client:)
        @dependency = dependency
        @github_client = github_client
      end

      def source_url
        return unless source

        case source.fetch("host")
        when "github" then github_client.web_endpoint + source.fetch("repo")
        when "bitbucket" then "https://bitbucket.org/" + source.fetch("repo")
        when "gitlab" then "https://gitlab.com/" + source.fetch("repo")
        else raise "Unexpected repo host '#{source.fetch('host')}'"
        end
      end

      def commits_url
        return @commits_url if @commits_url_lookup_attempted

        @commits_url_lookup_attempted = true
        @commits_url ||= look_up_commits_url
      end

      def changelog_url
        return @changelog_url if @changelog_url_lookup_attempted

        @changelog_url_lookup_attempted = true
        @changelog_url ||= look_up_changelog_url
      end

      def release_url
        return @release_url if @release_url_lookup_attempted

        @release_url_lookup_attempted = true
        @release_url ||= look_up_release_url
      end

      def latest_version
        NotImplementedError
      end

      private

      def source
        return @source if @source_lookup_attempted
        @source_lookup_attempted = true
        @source = look_up_source
      end

      def look_up_changelog_url
        files = fetch_dependency_file_list
        file = files.find { |f| CHANGELOG_NAMES.any? { |w| f.name =~ /#{w}/i } }

        file&.html_url
      end

      def look_up_release_url
        releases = fetch_dependency_releases

        release_regex = version_regex(dependency.version)
        release = releases.find do |r|
          [r.name, r.tag_name].any? { |nm| release_regex.match?(nm.to_s) }
        end
        return unless release

        unless dependency.previous_version
          return build_releases_index_url(releases: releases, release: release)
        end

        old_release_regex = version_regex(dependency.previous_version)
        previous_release = releases.find do |r|
          [r.name, r.tag_name].any? { |nm| old_release_regex.match?(nm.to_s) }
        end

        if previous_release &&
           (releases.index(previous_release) - releases.index(release)) == 1
          # No intermediate releases - link to release notes for this version
          release.html_url
        else
          # There have been intermediate releases, so link to release notes
          # index view
          build_releases_index_url(releases: releases, release: release)
        end
      rescue Octokit::NotFound
        nil
      end

      def look_up_commits_url
        return unless source_url

        tags = fetch_dependency_tags

        current_version = dependency.version
        previous_version = dependency.previous_version
        current_tag = tags.find { |t| t =~ version_regex(current_version) }
        previous_tag = tags.find { |t| t =~ version_regex(previous_version) }

        build_compare_commits_url(current_tag, previous_tag)
      end

      def look_up_source
        raise NotImplementedError
      end

      def version_regex(version)
        /(?:[^0-9\.]|\A)#{Regexp.escape(version || "unknown")}\z/
      end

      def fetch_dependency_file_list
        return [] unless source

        case source.fetch("host")
        when "github"
          github_client.contents(source["repo"])
        when "bitbucket"
          fetch_bitbucket_file_list
        when "gitlab"
          gitlab_client.repo_tree(source["repo"]).map do |file|
            OpenStruct.new(
              name: file.name,
              html_url: "#{source_url}/blob/master/#{file.path}"
            )
          end
        else raise "Unexpected repo host '#{source.fetch('host')}'"
        end
      rescue Octokit::NotFound, Gitlab::Error::NotFound
        []
      end

      def fetch_dependency_tags
        return [] unless source

        case source.fetch("host")
        when "github"
          github_client.tags(source["repo"], per_page: 100).map(&:name)
        when "bitbucket"
          fetch_bitbucket_tags
        when "gitlab"
          gitlab_client.tags(source["repo"]).map(&:name)
        else raise "Unexpected repo host '#{source.fetch('host')}'"
        end
      rescue Octokit::NotFound, Gitlab::Error::NotFound
        []
      end

      def fetch_dependency_releases
        return [] unless source

        case source.fetch("host")
        when "github"
          github_client.releases(source["repo"]).sort_by(&:id).reverse
        when "bitbucket"
          [] # Bitbucket doesn't support releases
        when "gitlab"
          releases = gitlab_client.tags(source["repo"]).
                     select(&:release).
                     sort_by { |r| r.commit.authored_date }.
                     reverse

          releases.map do |tag|
            OpenStruct.new(
              name: tag.name,
              tag_name: tag.release.tag_name,
              html_url: "#{source_url}/tags/#{tag.name}"
            )
          end
        else raise "Unexpected repo host '#{source.fetch('host')}'"
        end
      rescue Octokit::NotFound, Gitlab::Error::NotFound
        []
      end

      def build_releases_index_url(releases:, release:)
        case source.fetch("host")
        when "github"
          if releases.first == release
            "#{source_url}/releases"
          else
            subsequent_release = releases[releases.index(release) - 1]
            "#{source_url}/releases?after=#{subsequent_release.tag_name}"
          end
        when "gitlab"
          "#{source_url}/tags"
        when "bitbucket"
          raise "Bitbucket doesn't support releases"
        else raise "Unexpected repo host '#{source.fetch('host')}'"
        end
      end

      def build_compare_commits_url(current_tag, previous_tag)
        case source.fetch("host")
        when "github"
          build_github_compare_url(current_tag, previous_tag)
        when "bitbucket"
          build_bitbucket_compare_url(current_tag, previous_tag)
        when "gitlab"
          build_gitlab_compare_url(current_tag, previous_tag)
        else raise "Unexpected repo host '#{source.fetch('host')}'"
        end
      end

      def build_github_compare_url(current_tag, previous_tag)
        if current_tag && previous_tag
          "#{source_url}/compare/#{previous_tag}...#{current_tag}"
        elsif current_tag
          "#{source_url}/commits/#{current_tag}"
        else
          "#{source_url}/commits"
        end
      end

      def build_bitbucket_compare_url(current_tag, previous_tag)
        if current_tag && previous_tag
          "#{source_url}/branches/compare/#{current_tag}..#{previous_tag}"
        elsif current_tag
          "#{source_url}/commits/tag/#{current_tag}"
        else
          "#{source_url}/commits"
        end
      end

      def build_gitlab_compare_url(current_tag, previous_tag)
        if current_tag && previous_tag
          "#{source_url}/compare/#{previous_tag}...#{current_tag}"
        elsif current_tag
          "#{source_url}/commits/#{current_tag}"
        else
          "#{source_url}/commits/master"
        end
      end

      def fetch_bitbucket_file_list
        url = "https://api.bitbucket.org/2.0/repositories/"\
              "#{source.fetch('repo')}/src?pagelen=100"
        response = Excon.get(url, middlewares: SharedHelpers.excon_middleware)
        return [] if response.status >= 300

        JSON.parse(response.body).fetch("values", []).map do |file|
          OpenStruct.new(
            name: file["path"].split("/").last,
            html_url: "#{source_url}/src/master/#{file['path']}"
          )
        end
      end

      def fetch_bitbucket_tags
        url = "https://api.bitbucket.org/2.0/repositories/"\
              "#{source.fetch('repo')}/refs/tags?pagelen=100"
        response = Excon.get(url, middlewares: SharedHelpers.excon_middleware)
        return [] if response.status >= 300

        JSON.parse(response.body).fetch("values", []).map { |tag| tag["name"] }
      end

      def gitlab_client
        @gitlab_client ||=
          Gitlab.client(
            endpoint: "https://gitlab.com/api/v4",
            private_token: ""
          )
      end
    end
  end
end
