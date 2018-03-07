# frozen_string_literal: true

require "json"
require "gitlab"
require "excon"

require "dependabot/github_client_with_retries"
require "dependabot/shared_helpers"
require "dependabot/metadata_finders/base"

module Dependabot
  module MetadataFinders
    class Base
      class CommitsUrlFinder
        attr_reader :source, :dependency, :credentials

        def initialize(source:, dependency:, credentials:)
          @source = source
          @dependency = dependency
          @credentials = credentials
        end

        def commits_url
          return unless source

          current_version = dependency.version
          previous_version = dependency.previous_version

          current_tag =
            if git_source?(dependency.requirements)
              current_version
            else
              dependency_tags.find { |t| t =~ version_regex(current_version) }
            end

          previous_tag =
            if git_source?(dependency.previous_requirements)
              previous_version || previous_ref
            else
              dependency_tags.find { |t| t =~ version_regex(previous_version) }
            end

          build_compare_commits_url(current_tag, previous_tag)
        end

        private

        # TODO: Refactor me so that Composer doesn't need to be special cased
        def git_source?(requirements)
          # Special case Composer, which uses git as a source but handles tags
          # internally
          return false if dependency.package_manager == "composer"

          sources = requirements.map { |r| r.fetch(:source) }.uniq.compact
          return false if sources.empty?
          raise "Multiple sources! #{sources.join(', ')}" if sources.count > 1
          source_type = sources.first[:type] || sources.first.fetch("type")
          source_type == "git"
        end

        def previous_ref
          return unless git_source?(dependency.previous_requirements)
          dependency.previous_requirements.map do |r|
            r.dig(:source, "ref") || r.dig(:source, :ref)
          end.compact.first
        end

        def version_regex(version)
          /(?:[^0-9\.]|\A)#{Regexp.escape(version || "unknown")}\z/
        end

        def dependency_tags
          @dependency_tags ||= fetch_dependency_tags
        end

        def fetch_dependency_tags
          return [] unless source

          case source.host
          when "github"
            github_client.tags(source.repo, per_page: 100).map(&:name)
          when "bitbucket"
            fetch_bitbucket_tags
          when "gitlab"
            gitlab_client.tags(source.repo).map(&:name)
          else raise "Unexpected repo host '#{source.host}'"
          end
        rescue Octokit::NotFound, Gitlab::Error::NotFound
          []
        end

        def build_compare_commits_url(current_tag, previous_tag)
          case source.host
          when "github"
            build_github_compare_url(current_tag, previous_tag)
          when "bitbucket"
            build_bitbucket_compare_url(current_tag, previous_tag)
          when "gitlab"
            build_gitlab_compare_url(current_tag, previous_tag)
          else raise "Unexpected repo host '#{source.host}'"
          end
        end

        def build_github_compare_url(current_tag, previous_tag)
          if current_tag && previous_tag
            "#{source.url}/compare/#{previous_tag}...#{current_tag}"
          elsif current_tag
            "#{source.url}/commits/#{current_tag}"
          else
            "#{source.url}/commits"
          end
        end

        def build_bitbucket_compare_url(current_tag, previous_tag)
          if current_tag && previous_tag
            "#{source.url}/branches/compare/#{current_tag}..#{previous_tag}"
          elsif current_tag
            "#{source.url}/commits/tag/#{current_tag}"
          else
            "#{source.url}/commits"
          end
        end

        def build_gitlab_compare_url(current_tag, previous_tag)
          if current_tag && previous_tag
            "#{source.url}/compare/#{previous_tag}...#{current_tag}"
          elsif current_tag
            "#{source.url}/commits/#{current_tag}"
          else
            "#{source.url}/commits/master"
          end
        end

        def fetch_bitbucket_tags
          url = "https://api.bitbucket.org/2.0/repositories/"\
                "#{source.repo}/refs/tags?pagelen=100"
          response = Excon.get(
            url,
            idempotent: true,
            middlewares: SharedHelpers.excon_middleware
          )
          return [] if response.status >= 300

          JSON.parse(response.body).
            fetch("values", []).
            map { |tag| tag["name"] }
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
