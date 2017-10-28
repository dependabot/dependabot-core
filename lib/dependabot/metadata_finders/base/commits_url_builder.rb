# frozen_string_literal: true

require "json"
require "gitlab"
require "octokit"
require "excon"

require "dependabot/shared_helpers"
require "dependabot/metadata_finders/base"

module Dependabot
  module MetadataFinders
    class Base
      class CommitsUrlBuilder
        attr_reader :source, :dependency, :github_client

        def initialize(source:, dependency:, github_client:)
          @source = source
          @dependency = dependency
          @github_client = github_client
        end

        def commits_url
          return unless source

          current_version = dependency.version
          previous_version = dependency.previous_version

          current_tag =
            if new_source_type == "git"
              current_version
            else
              dependency_tags.find { |t| t =~ version_regex(current_version) }
            end

          previous_tag =
            if old_source_type == "git"
              previous_version || previous_ref
            else
              dependency_tags.find { |t| t =~ version_regex(previous_version) }
            end

          build_compare_commits_url(current_tag, previous_tag)
        end

        private

        # TODO: refactor so this isn't duplicated with base class
        def source_url
          case source.fetch("host")
          when "github" then github_client.web_endpoint + source.fetch("repo")
          when "bitbucket" then "https://bitbucket.org/" + source.fetch("repo")
          when "gitlab" then "https://gitlab.com/" + source.fetch("repo")
          else raise "Unexpected repo host '#{source.fetch('host')}'"
          end
        end

        def new_source_type
          sources =
            dependency.requirements.map { |r| r.fetch(:source) }.uniq.compact

          return "default" if sources.empty?
          raise "Multiple sources! #{sources.join(', ')}" if sources.count > 1
          sources.first[:type] || sources.first.fetch("type")
        end

        def old_source_type
          sources = dependency.previous_requirements.
                    map { |r| r.fetch(:source) }.uniq.compact

          return "default" if sources.empty?
          raise "Multiple sources! #{sources.join(', ')}" if sources.count > 1
          sources.first[:type] || sources.first.fetch("type")
        end

        def previous_ref
          return unless old_source_type == "git"
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

        def fetch_bitbucket_tags
          url = "https://api.bitbucket.org/2.0/repositories/"\
                "#{source.fetch('repo')}/refs/tags?pagelen=100"
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
      end
    end
  end
end
