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
      class ChangelogFinder
        # Earlier entries are preferred
        CHANGELOG_NAMES = %w(changelog history news changes release).freeze

        attr_reader :source, :dependency, :credentials

        def initialize(source:, dependency:, credentials:)
          @source = source
          @dependency = dependency
          @credentials = credentials
        end

        def changelog_url
          return unless source

          # Changelog won't be relevant for a git commit bump
          return if git_source?(dependency.requirements) && !ref_changed?

          files = dependency_file_list.select { |f| f.type == "file" }

          CHANGELOG_NAMES.each do |name|
            file = files.find { |f| f.name =~ /#{name}/i }
            return file.html_url if file
          end

          nil
        end

        private

        def dependency_file_list
          @dependency_file_list ||= fetch_dependency_file_list
        end

        def fetch_dependency_file_list
          case source.host
          when "github" then fetch_github_file_list
          when "bitbucket" then fetch_bitbucket_file_list
          when "gitlab" then fetch_gitlab_file_list
          else raise "Unexpected repo host '#{source.host}'"
          end
        rescue Octokit::NotFound, Gitlab::Error::NotFound
          []
        end

        def fetch_github_file_list
          files = []

          if source.directory
            files += github_client.contents(source.repo, path: source.directory)
          end

          files += github_client.contents(source.repo)

          if files.any? { |f| f.name == "docs" && f.type == "dir" }
            files = github_client.contents(source.repo, path: "docs") + files
          end

          files
        end

        def fetch_bitbucket_file_list
          url = "https://api.bitbucket.org/2.0/repositories/"\
                "#{source.repo}/src?pagelen=100"
          response = Excon.get(
            url,
            idempotent: true,
            middlewares: SharedHelpers.excon_middleware
          )
          return [] if response.status >= 300

          JSON.parse(response.body).fetch("values", []).map do |file|
            OpenStruct.new(
              name: file.fetch("path").split("/").last,
              type: file.fetch("type") == "commit_file" ? "file" : file["type"],
              html_url: "#{source.url}/src/master/#{file['path']}"
            )
          end
        end

        def fetch_gitlab_file_list
          gitlab_client.repo_tree(source.repo).map do |file|
            OpenStruct.new(
              name: file.name,
              type: file.type == "blob" ? "file" : file.type,
              html_url: "#{source.url}/blob/master/#{file.path}"
            )
          end
        end

        def previous_ref
          dependency.previous_requirements.map do |r|
            r.dig(:source, "ref") || r.dig(:source, :ref)
          end.compact.first
        end

        def new_ref
          dependency.requirements.map do |r|
            r.dig(:source, "ref") || r.dig(:source, :ref)
          end.compact.first
        end

        def ref_changed?
          previous_ref && new_ref && previous_ref != new_ref
        end

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

          @github_client ||= Octokit::Client.new(access_token: access_token)
        end
      end
    end
  end
end
