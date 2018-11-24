# frozen_string_literal: true

require "excon"

require "dependabot/clients/github_with_retries"
require "dependabot/clients/gitlab"
require "dependabot/clients/bitbucket"
require "dependabot/shared_helpers"
require "dependabot/metadata_finders/base"

module Dependabot
  module MetadataFinders
    class Base
      class ChangelogFinder
        require_relative "changelog_pruner"

        # Earlier entries are preferred
        CHANGELOG_NAMES = %w(changelog history news changes release).freeze

        attr_reader :source, :dependency, :credentials

        def initialize(source:, dependency:, credentials:)
          @source = source
          @dependency = dependency
          @credentials = credentials
        end

        def changelog_url
          changelog&.html_url
        end

        def changelog_text
          return unless full_changelog_text

          ChangelogPruner.new(
            dependency: dependency,
            changelog_text: full_changelog_text
          ).pruned_text
        end

        def upgrade_guide_url
          upgrade_guide&.html_url
        end

        def upgrade_guide_text
          return unless upgrade_guide

          @upgrade_guide_text ||= fetch_file_text(upgrade_guide)
        end

        private

        def changelog
          return unless source

          # Changelog won't be relevant for a git commit bump
          return if git_source? && !ref_changed?
          return unless default_branch_changelog
          return default_branch_changelog unless new_version

          if fetch_file_text(default_branch_changelog)&.include?(new_version)
            return default_branch_changelog
          end

          default_branch_changelog
        end

        def default_branch_changelog
          return unless source

          @default_branch_changelog ||=
            begin
              files =
                dependency_file_list.
                select { |f| f.type == "file" }.
                reject { |f| f.name.end_with?(".sh") }.
                reject { |f| f.size > 1_000_000 }

              CHANGELOG_NAMES.each do |name|
                candidates = files.select { |f| f.name =~ /#{name}/i }
                file = candidates.first if candidates.one?
                file ||=
                  candidates.find do |f|
                    candidates -= [f] && next if fetch_file_text(f).nil?
                    new_version && fetch_file_text(f).include?(new_version)
                  end
                file ||= candidates.max_by(&:size)
                return file if file
              end

              nil
            end
        end

        def full_changelog_text
          return unless changelog

          fetch_file_text(changelog)
        end

        def fetch_file_text(file)
          @file_text ||= {}

          unless @file_text.key?(file.path)
            @file_text[file.path] =
              case source.provider
              when "github" then fetch_github_file(file)
              when "gitlab" then fetch_gitlab_file(file)
              when "bitbucket" then fetch_bitbucket_file(file)
              else raise "Unsupported provider '#{source.provider}"
              end
          end

          return unless @file_text[file.path].valid_encoding?

          @file_text[file.path].force_encoding("UTF-8").encode.sub(/\n*\z/, "")
        end

        def fetch_github_file(file)
          # Hitting the download URL directly causes encoding problems
          raw_content = github_client.get(file.url).content
          Base64.decode64(raw_content).force_encoding("UTF-8").encode
        end

        def fetch_gitlab_file(file)
          Excon.get(
            file.download_url,
            idempotent: true,
            **SharedHelpers.excon_defaults
          ).body
        end

        def fetch_bitbucket_file(file)
          bitbucket_client.get(file.download_url).body
        end

        def upgrade_guide
          return unless source

          # Upgrade guide usually won't be relevant for bumping anything other
          # than the major version
          return unless major_version_upgrade?

          dependency_file_list.
            select { |f| f.type == "file" }.
            select { |f| f.name.casecmp("upgrade.md").zero? }.
            reject { |f| f.size > 1_000_000 }.
            max_by(&:size)
        end

        def dependency_file_list
          @dependency_file_list ||= fetch_dependency_file_list
        end

        def fetch_dependency_file_list
          case source.provider
          when "github" then fetch_github_file_list
          when "bitbucket" then fetch_bitbucket_file_list
          when "gitlab" then fetch_gitlab_file_list
          else raise "Unexpected repo provider '#{source.provider}'"
          end
        end

        def fetch_github_file_list
          files = []

          if source.directory
            files += github_client.contents(source.repo, path: source.directory)
          end

          files += github_client.contents(source.repo)

          %w(doc docs).each do |dir_name|
            if files.any? { |f| f.name == dir_name && f.type == "dir" }
              files += github_client.contents(source.repo, path: dir_name)
            end
          end

          files
        rescue Octokit::NotFound
          []
        end

        def fetch_bitbucket_file_list
          bitbucket_client.fetch_repo_contents(source.repo).map do |file|
            OpenStruct.new(
              name: file.fetch("path").split("/").last,
              type: file.fetch("type") == "commit_file" ? "file" : file["type"],
              size: file.fetch("size", 0),
              html_url: "#{source.url}/src/master/#{file['path']}",
              download_url: "#{source.url}/raw/master/#{file['path']}"
            )
          end
        rescue Dependabot::Clients::Bitbucket::NotFound
          []
        end

        def fetch_gitlab_file_list
          gitlab_client.repo_tree(source.repo).map do |file|
            OpenStruct.new(
              name: file.name,
              type: file.type == "blob" ? "file" : file.type,
              size: 0, # GitLab doesn't return file size
              html_url: "#{source.url}/blob/master/#{file.path}",
              download_url: "#{source.url}/raw/master/#{file.path}"
            )
          end
        rescue Gitlab::Error::NotFound
          []
        end

        def new_version
          @new_version ||= git_source? ? new_ref : dependency.version
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
        def git_source?
          # Special case Composer, which uses git as a source but handles tags
          # internally
          return false if dependency.package_manager == "composer"

          requirements = dependency.requirements
          sources = requirements.map { |r| r.fetch(:source) }.uniq.compact
          return false if sources.empty?
          raise "Multiple sources! #{sources.join(', ')}" if sources.count > 1

          source_type = sources.first[:type] || sources.first.fetch("type")
          source_type == "git"
        end

        def major_version_upgrade?
          return false unless dependency.version&.match?(/^\d/)
          return false unless dependency.previous_version&.match?(/^\d/)

          dependency.version.split(".").first.to_i -
            dependency.previous_version.split(".").first.to_i >= 1
        end

        def gitlab_client
          @gitlab_client ||= Dependabot::Clients::Gitlab.
                             for_gitlab_dot_com(credentials: credentials)
        end

        def github_client
          @github_client ||= Dependabot::Clients::GithubWithRetries.
                             for_github_dot_com(credentials: credentials)
        end

        def bitbucket_client
          @bitbucket_client ||= Dependabot::Clients::Bitbucket.
                                for_bitbucket_dot_org(credentials: credentials)
        end
      end
    end
  end
end
