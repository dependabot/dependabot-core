# frozen_string_literal: true

require "gitlab"

require "dependabot/github_client_with_retries"
require "dependabot/metadata_finders/base"

module Dependabot
  module MetadataFinders
    class Base
      class ReleaseFinder
        attr_reader :dependency, :credentials, :source

        def initialize(source:, dependency:, credentials:)
          @source = source
          @dependency = dependency
          @credentials = credentials
        end

        def releases_url
          return unless source
          case source.host
          when "github" then "#{source.url}/releases"
          when "gitlab" then "#{source.url}/tags"
          when "bitbucket" then nil
          else raise "Unexpected repo host '#{source.host}'"
          end
        end

        def releases_text
          return unless updated_release
          return if updated_release.body.nil? || updated_release.body == ""

          relevant_releases.map do |r|
            title = "## #{r.name.to_s != '' ? r.name : r.tag_name}\n"
            body =
              if r.body.gsub(/\n*\z/m, "") == ""
                "No release notes provided."
              else
                r.body.gsub(/\n*\z/m, "")
              end

            title + body
          end.join("\n\n")
        end

        private

        def all_releases
          @all_releases ||= fetch_dependency_releases
        end

        def relevant_releases
          if dependency.previous_version && previous_release
            [updated_release, *intermediate_releases]
          else
            [updated_release]
          end
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

        def intermediate_releases
          intermediate_release_count =
            all_releases.index(previous_release) -
            all_releases.index(updated_release) -
            1

          intermediate_releases = all_releases.slice(
            all_releases.index(updated_release) + 1,
            intermediate_release_count
          )

          unless Gem::Version.correct?(dependency.version)
            return intermediate_releases
          end

          intermediate_releases.reject do |release|
            cleaned_tag = release.tag_name.gsub(/^[^0-9\.]*/, "")

            # Don't reject anything we can't be certain of
            next false unless Gem::Version.correct?(cleaned_tag)

            # Do reject any releases that are greater than the version we're
            # updating to (e.g., if two major versions are being maintained)
            Gem::Version.new(cleaned_tag) > Gem::Version.new(dependency.version)
          end
        end

        def version_regex(version)
          /(?:[^0-9\.]|\A)#{Regexp.escape(version || "unknown")}\z/
        end

        def fetch_dependency_releases
          return [] unless source

          case source.host
          when "github" then fetch_github_releases
          when "bitbucket" then [] # Bitbucket doesn't support releases
          when "gitlab" then fetch_gitlab_releases
          else raise "Unexpected repo host '#{source.host}'"
          end
        end

        def fetch_github_releases
          releases = github_client.releases(source.repo)
          clean_release_names =
            releases.map { |r| r.tag_name.gsub(/^[^0-9\.]*/, "") }

          if clean_release_names.all? { |nm| Gem::Version.correct?(nm) }
            releases.sort_by do |r|
              Gem::Version.new(r.tag_name.gsub(/^[^0-9\.]*/, ""))
            end.reverse
          else
            releases.sort_by(&:id).reverse
          end
        rescue Octokit::NotFound
          []
        end

        def fetch_gitlab_releases
          releases =
            gitlab_client.
            tags(source.repo).
            select(&:release).
            sort_by { |r| r.commit.authored_date }.
            reverse

          releases.map do |tag|
            OpenStruct.new(
              name: tag.name,
              tag_name: tag.release.tag_name,
              body: tag.release.description,
              html_url: "#{source.url}/tags/#{tag.name}"
            )
          end
        rescue Gitlab::Error::NotFound
          []
        end

        def gitlab_client
          @gitlab_client ||=
            Gitlab.client(
              endpoint: "https://gitlab.com/api/v4",
              private_token: ""
            )
        end

        def github_client
          access_token =
            credentials.
            find { |cred| cred["host"] == "github.com" }&.
            fetch("password")

          @github_client ||=
            Dependabot::GithubClientWithRetries.new(access_token: access_token)
        end
      end
    end
  end
end
