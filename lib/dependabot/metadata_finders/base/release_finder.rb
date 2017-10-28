# frozen_string_literal: true

require "gitlab"
require "octokit"

require "dependabot/metadata_finders/base"

module Dependabot
  module MetadataFinders
    class Base
      class ReleaseFinder
        attr_reader :dependency, :github_client, :source

        def initialize(source:, dependency:, github_client:)
          @source = source
          @dependency = dependency
          @github_client = github_client
        end

        def release_url
          return nil unless updated_release
          return releases_index_url unless dependency.previous_version

          intermediate_release_count =
            all_releases.index(previous_release) -
            all_releases.index(updated_release) -
            1

          if previous_release && intermediate_release_count.zero?
            updated_release.html_url
          else
            releases_index_url
          end
        end

        private

        # TODO: refactor so this isn't duplicated with base class
        def source_url
          return unless source

          case source.fetch("host")
          when "github" then github_client.web_endpoint + source.fetch("repo")
          when "bitbucket" then "https://bitbucket.org/" + source.fetch("repo")
          when "gitlab" then "https://gitlab.com/" + source.fetch("repo")
          else raise "Unexpected repo host '#{source.fetch('host')}'"
          end
        end

        def all_releases
          @releases ||= fetch_dependency_releases
        end

        def updated_release
          release_regex = version_regex(dependency.version)
          all_releases.find do |r|
            [r.name, r.tag_name].any? { |nm| release_regex.match?(nm.to_s) }
          end
        end

        def previous_release
          release_regex = version_regex(dependency.previous_version)
          all_releases.find do |r|
            [r.name, r.tag_name].any? { |nm| release_regex.match?(nm.to_s) }
          end
        end

        def releases_index_url
          build_releases_index_url(
            releases: all_releases,
            release: updated_release
          )
        end

        def version_regex(version)
          /(?:[^0-9\.]|\A)#{Regexp.escape(version || "unknown")}\z/
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
end
