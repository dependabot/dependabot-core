# frozen_string_literal: true

require "gitlab"

require "dependabot/github_client_with_retries"
require "dependabot/metadata_finders/base"
require "dependabot/utils"

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
          return unless relevant_releases.any?
          return if relevant_releases.all? { |r| r.body.nil? || r.body == "" }

          relevant_releases.map do |r|
            title = "## #{r.name.to_s != '' ? r.name : r.tag_name}\n"
            body =
              if r.body.to_s.gsub(/\n*\z/m, "") == ""
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
          releases = releases_since_previous_version

          if updated_release && version_class.correct?(dependency.version)
            releases = filter_releases_using_updated_release(releases)
            filter_releases_using_updated_version(releases, conservative: true)
          elsif updated_release
            filter_releases_using_updated_release(releases)
          elsif version_class.correct?(dependency.version)
            filter_releases_using_updated_version(releases, conservative: false)
          else
            [updated_release].compact
          end
        end

        def releases_since_previous_version
          previous_version = dependency.previous_version
          return [updated_release].compact unless previous_version

          if previous_release && version_class.correct?(previous_version)
            releases = filter_releases_using_previous_release(all_releases)
            filter_releases_using_previous_version(releases, conservative: true)
          elsif previous_release
            filter_releases_using_previous_release(all_releases)
          elsif version_class.correct?(previous_version)
            filter_releases_using_previous_version(
              all_releases,
              conservative: false
            )
          else
            [updated_release].compact
          end
        end

        def filter_releases_using_previous_release(releases)
          releases.first(releases.index(previous_release))
        end

        def filter_releases_using_updated_release(releases)
          releases[releases.index(updated_release)..-1]
        end

        def filter_releases_using_previous_version(releases, conservative:)
          previous_version = version_class.new(dependency.previous_version)

          releases.reject do |release|
            cleaned_tag = release.tag_name.gsub(/^[^0-9\.]*/, "")
            cleaned_name = release.name&.gsub(/^[^0-9\.]*/, "")

            tag_version = [cleaned_tag, cleaned_name].compact.reject(&:empty?).
                          select { |nm| version_class.correct?(nm) }.
                          map { |nm| version_class.new(nm) }.max

            next conservative unless tag_version

            # Reject any releases that are less than the previous version
            # (e.g., if two major versions are being maintained)
            tag_version <= previous_version
          end
        end

        def filter_releases_using_updated_version(releases, conservative:)
          updated_version = version_class.new(dependency.version)

          releases.reject do |release|
            cleaned_tag = release.tag_name.gsub(/^[^0-9\.]*/, "")
            cleaned_name = release.name&.gsub(/^[^0-9\.]*/, "")

            tag_version = [cleaned_tag, cleaned_name].compact.reject(&:empty?).
                          select { |nm| version_class.correct?(nm) }.
                          map { |nm| version_class.new(nm) }.min

            next conservative unless tag_version

            # Reject any releases that are greater than the updated version
            # (e.g., if two major versions are being maintained)
            tag_version > updated_version
          end
        end

        def updated_release
          release_for_version(dependency.version)
        end

        def previous_release
          release_for_version(dependency.previous_version)
        end

        def release_for_version(version)
          return nil unless version
          release_regex = version_regex(version)
          # Doing two loops looks inefficient, but it ensures consistency
          all_releases.find { |r| release_regex.match?(r.tag_name.to_s) } ||
            all_releases.find { |r| release_regex.match?(r.name.to_s) }
        end

        def version_regex(version)
          /(?:[^0-9\.]|\A)#{Regexp.escape(version || "unknown")}\z/
        end

        def version_class
          Utils.version_class_for_package_manager(dependency.package_manager)
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

          if clean_release_names.all? { |nm| version_class.correct?(nm) }
            releases.sort_by do |r|
              version_class.new(r.tag_name.gsub(/^[^0-9\.]*/, ""))
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
