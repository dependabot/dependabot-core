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

          new_version = dependency.version
          previous_version = dependency.previous_version

          new_tag =
            if git_source?(dependency.requirements) then new_version
            else dependency_tags.find { |t| t =~ version_regex(new_version) }
            end

          previous_tag =
            if git_source?(dependency.previous_requirements)
              previous_version || previous_ref
            else
              dependency_tags.find { |t| t =~ version_regex(previous_version) }
            end

          build_compare_commits_url(new_tag, previous_tag)
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

        def build_compare_commits_url(new_tag, previous_tag)
          path =
            case source.host
            when "github" then github_compare_path(new_tag, previous_tag)
            when "bitbucket" then bitbucket_compare_path(new_tag, previous_tag)
            when "gitlab" then gitlab_compare_path(new_tag, previous_tag)
            else raise "Unexpected repo host '#{source.host}'"
            end

          "#{source.url}/#{path}"
        end

        def github_compare_path(new_tag, previous_tag)
          if new_tag && previous_tag
            "compare/#{previous_tag}...#{new_tag}"
          elsif new_tag
            "commits/#{new_tag}"
          else
            "commits"
          end
        end

        def bitbucket_compare_path(new_tag, previous_tag)
          if new_tag && previous_tag
            "branches/compare/#{new_tag}..#{previous_tag}"
          elsif new_tag
            "commits/tag/#{new_tag}"
          else
            "commits"
          end
        end

        def gitlab_compare_path(new_tag, previous_tag)
          if new_tag && previous_tag
            "compare/#{previous_tag}...#{new_tag}"
          elsif new_tag
            "commits/#{new_tag}"
          else
            "commits/master"
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
