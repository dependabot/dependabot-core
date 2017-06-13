# frozen_string_literal: true
module Dependabot
  module MetadataFinders
    class Base
      SOURCE_REGEX = %r{
        (?<host>github(?=\.com)|bitbucket(?=\.org))
        (?:\.com|\.org)/
        (?<repo>[^/]+/(?:(?!\.git)[^/])+)[\./]?
      }x
      CHANGELOG_NAMES = %w(changelog history news changes).freeze

      attr_reader :dependency, :github_client

      def initialize(dependency:, github_client:)
        @dependency = dependency
        @github_client = github_client
      end

      def source
        return @source if @source_lookup_attempted
        @source_lookup_attempted = true
        @source = look_up_source
      end

      def source_url
        return unless source

        case source.fetch("host")
        when nil then nil
        when "github" then github_client.web_endpoint + source.fetch("repo")
        when "bitbucket" then "https://bitbucket.org/" + source.fetch("repo")
        else raise "Unexpected repo host '#{source.fetch('host')}'"
        end
      end

      def commits_url
        return @commits_url if @commits_url_lookup_attempted

        look_up_commits_url
      end

      def changelog_url
        return @changelog_url if @changelog_url_lookup_attempted

        look_up_changelog_url
      end

      def release_url
        return @release_url if @release_url_lookup_attempted

        look_up_release_url
      end

      private

      def github_repo?
        source && source["host"] == "github"
      end

      def look_up_changelog_url
        @changelog_url_lookup_attempted = true

        return @changelog_url = nil unless github_repo?

        files = github_client.contents(source["repo"])
        file = files.find { |f| CHANGELOG_NAMES.any? { |w| f.name =~ /#{w}/i } }

        @changelog_url = file.nil? ? nil : file.html_url
      rescue Octokit::NotFound
        @changelog_url = nil
      end

      def look_up_release_url
        @release_url_lookup_attempted = true

        return @release_url = nil unless github_repo?

        release_regex = version_regex(dependency.version)
        release = github_client.releases(source["repo"]).find do |r|
          r.name.to_s =~ release_regex || r.tag_name.to_s =~ release_regex
        end

        @release_url = release&.html_url
      rescue Octokit::NotFound
        @release_url = nil
      end

      def look_up_commits_url
        @commits_url_lookup_attempted = true

        return @commits_url = nil unless github_repo?

        @tags ||= github_client.tags(source["repo"]).map { |tag| tag["name"] }

        current_version = dependency.version
        previous_version = dependency.previous_version
        current_tag = @tags.find { |t| t =~ version_regex(current_version) }
        previous_tag = @tags.find { |t| t =~ version_regex(previous_version) }

        @commits_url =
          if current_tag && previous_tag
            "#{source_url}/compare/#{previous_tag}...#{current_tag}"
          elsif current_tag
            "#{source_url}/commits/#{current_tag}"
          else
            "#{source_url}/commits"
          end
      rescue Octokit::NotFound
        []
      end

      def look_up_source
        raise NotImplementedError
      end

      def version_regex(version)
        /[^0-9\.]#{Regexp.escape(version)}\z/
      end
    end
  end
end
