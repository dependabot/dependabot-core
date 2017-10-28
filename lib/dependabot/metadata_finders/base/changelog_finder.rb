# frozen_string_literal: true

require "json"
require "gitlab"
require "octokit"
require "excon"

require "dependabot/metadata_finders/base"

module Dependabot
  module MetadataFinders
    class Base
      class ChangelogFinder
        # Earlier entries are preferred
        CHANGELOG_NAMES = %w(changelog history news changes release).freeze

        attr_reader :github_client, :source

        def initialize(source:, github_client:)
          @github_client = github_client
          @source = source
        end

        def changelog_url
          return unless source

          files = dependency_file_list.select { |f| f.type == "file" }

          CHANGELOG_NAMES.each do |name|
            file = files.find { |f| f.name =~ /#{name}/i }
            return file.html_url if file
          end

          nil
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

        def dependency_file_list
          @dependency_file_list ||= fetch_dependency_file_list
        end

        def fetch_dependency_file_list
          case source.fetch("host")
          when "github" then github_client.contents(source["repo"])
          when "bitbucket" then fetch_bitbucket_file_list
          when "gitlab" then fetch_gitlab_file_list
          else raise "Unexpected repo host '#{source.fetch('host')}'"
          end
        rescue Octokit::NotFound, Gitlab::Error::NotFound
          []
        end

        def fetch_bitbucket_file_list
          url = "https://api.bitbucket.org/2.0/repositories/"\
                "#{source.fetch('repo')}/src?pagelen=100"
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
              html_url: "#{source_url}/src/master/#{file['path']}"
            )
          end
        end

        def fetch_gitlab_file_list
          gitlab_client.repo_tree(source["repo"]).map do |file|
            OpenStruct.new(
              name: file.name,
              type: file.type == "blob" ? "file" : file.type,
              html_url: "#{source_url}/blob/master/#{file.path}"
            )
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
