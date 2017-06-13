# frozen_string_literal: true
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

      def source
        return @source if @source_lookup_attempted
        @source_lookup_attempted = true
        @source = look_up_source
      end

      def look_up_changelog_url
        @changelog_url_lookup_attempted = true

        files = fetch_dependency_file_tree
        file = files.find { |f| CHANGELOG_NAMES.any? { |w| f.name =~ /#{w}/i } }

        @changelog_url = file&.html_url
      end

      def look_up_release_url
        @release_url_lookup_attempted = true

        releases = fetch_dependency_releases

        release_regex = version_regex(dependency.version)
        release = releases.find do |r|
          r.name.to_s =~ release_regex || r.tag_name.to_s =~ release_regex
        end

        @release_url = release&.html_url
      rescue Octokit::NotFound
        @release_url = nil
      end

      def look_up_commits_url
        @commits_url_lookup_attempted = true
        return @commits_url = nil if source_url.nil?

        tags = fetch_dependency_tags

        current_version = dependency.version
        previous_version = dependency.previous_version
        current_tag = tags.find { |t| t =~ version_regex(current_version) }
        previous_tag = tags.find { |t| t =~ version_regex(previous_version) }

        @commits_url =
          if current_tag && previous_tag
            "#{source_url}/compare/#{previous_tag}...#{current_tag}"
          elsif current_tag
            "#{source_url}/commits/#{current_tag}"
          elsif source.fetch("host") == "gitlab"
            "#{source_url}/commits/master"
          else
            "#{source_url}/commits"
          end
      end

      def look_up_source
        raise NotImplementedError
      end

      def version_regex(version)
        /[^0-9\.]#{Regexp.escape(version)}\z/
      end

      def fetch_dependency_file_tree
        return [] unless source

        case source.fetch("host")
        when "github"
          github_client.contents(source["repo"])
        when "bitbucket"
          [] # TODO: add Bitbucket support
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
          github_client.tags(source["repo"]).map(&:name)
        when "bitbucket"
          [] # TODO: add Bitbucket support
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
          github_client.releases(source["repo"])
        when "bitbucket"
          [] # TODO: add Bitbucket support
        when "gitlab"
          gitlab_client.tags(source["repo"]).select(&:release).map do |tag|
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
