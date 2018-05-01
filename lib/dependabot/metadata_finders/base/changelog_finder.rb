# frozen_string_literal: true

require "json"
require "gitlab"
require "excon"

require "dependabot/github_client_with_retries"
require "dependabot/shared_helpers"
require "dependabot/metadata_finders/base"

# rubocop:disable Metrics/ClassLength
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
          changelog&.html_url
        end

        # rubocop:disable Metrics/PerceivedComplexity
        # rubocop:disable Metrics/CyclomaticComplexity
        def changelog_text
          return unless full_changelog_text

          changelog_lines = full_changelog_text.split("\n")

          slice_range =
            if old_version_changelog_line && new_version_changelog_line
              if old_version_changelog_line < new_version_changelog_line
                Range.new(old_version_changelog_line, -1)
              else
                Range.new(new_version_changelog_line,
                          old_version_changelog_line - 1)
              end
            elsif old_version_changelog_line
              return if old_version_changelog_line.zero?

              # Assumes changelog is in descending order
              Range.new(0, old_version_changelog_line - 1)
            elsif new_version_changelog_line
              # Assumes changelog is in descending order
              Range.new(new_version_changelog_line, -1)
            else
              return unless changelog_contains_relevant_versions?

              # If the changelog contains any relevant versions, return it in
              # full. We could do better here by fully parsing the changelog
              Range.new(0, -1)
            end

          changelog_lines.slice(slice_range).join("\n").sub(/\n*\z/, "")
        end
        # rubocop:enable Metrics/PerceivedComplexity
        # rubocop:enable Metrics/CyclomaticComplexity

        def upgrade_guide_url
          upgrade_guide&.html_url
        end

        def upgrade_guide_text
          return unless upgrade_guide

          @upgrade_guide_text ||=
            if source.host == "github"
              # Hitting the download URL directly causes encoding problems
              raw_content = github_client.contents(
                source.repo,
                path: upgrade_guide.path
              ).content
              Base64.decode64(raw_content).force_encoding("UTF-8").encode
            else
              Excon.get(
                upgrade_guide.download_url,
                idempotent: true,
                middlewares: SharedHelpers.excon_middleware
              ).body
            end

          return unless @upgrade_guide_text.valid_encoding?
          @upgrade_guide_text.force_encoding("UTF-8").encode.sub(/\n*\z/, "")
        end

        private

        def changelog
          return unless source

          # Changelog won't be relevant for a git commit bump
          return if git_source? && !ref_changed?

          files =
            dependency_file_list.
            select { |f| f.type == "file" }.
            reject { |f| f.name.end_with?(".sh") }.
            reject { |f| f.size > 1_000_000 }

          CHANGELOG_NAMES.each do |name|
            file = files.select { |f| f.name =~ /#{name}/i }.max_by(&:size)
            return file if file
          end

          nil
        end

        def full_changelog_text
          return unless changelog

          @full_changelog_text ||=
            if source.host == "github"
              # Hitting the download URL directly causes encoding problems
              raw_content = github_client.contents(
                source.repo,
                path: changelog.path
              ).content
              Base64.decode64(raw_content).force_encoding("UTF-8").encode
            else
              Excon.get(
                changelog.download_url,
                idempotent: true,
                middlewares: SharedHelpers.excon_middleware
              ).body
            end
          return unless @full_changelog_text.valid_encoding?
          @full_changelog_text.force_encoding("UTF-8").encode.sub(/\n*\z/, "")
        end

        def old_version_changelog_line
          old_version = git_source? ? previous_ref : dependency.previous_version
          return nil unless old_version
          changelog_line_for_version(old_version)
        end

        def new_version_changelog_line
          new_version = git_source? ? new_ref : dependency.version
          return nil unless new_version
          changelog_line_for_version(new_version)
        end

        # rubocop:disable Metrics/CyclomaticComplexity
        # rubocop:disable Metrics/PerceivedComplexity
        def changelog_line_for_version(version)
          raise "No changelog text" unless full_changelog_text
          return nil unless version
          version = version.gsub(/^v/, "")

          changelog_lines = full_changelog_text.split("\n")

          changelog_lines.find_index.with_index do |line, index|
            next false unless line.include?(version)
            next true if line.start_with?("#", "!")
            next true if line.match?(/^v?#{Regexp.escape(version)}:?/)
            next true if line.match?(/^\d{4}-\d{2}-\d{2}/)
            next true if changelog_lines[index + 1]&.match?(/^[=-]+$/)
            false
          end
        end
        # rubocop:enable Metrics/CyclomaticComplexity
        # rubocop:enable Metrics/PerceivedComplexity

        def changelog_contains_relevant_versions?
          # Assume the changelog is relevant if we can't parse the new version
          return true unless version_class.correct?(dependency.version)

          # Assume the changelog is relevant if it mentions the new version
          # anywhere
          return true if full_changelog_text.include?(dependency.version)

          # Otherwise check if any intermediate versions are included in headers
          versions_in_changelog_headers.any? do |version|
            next false unless version <= version_class.new(dependency.version)
            next true unless dependency.previous_version
            next true unless version_class.correct?(dependency.previous_version)
            version > version_class.new(dependency.previous_version)
          end
        end

        def versions_in_changelog_headers
          changelog_lines = full_changelog_text.split("\n")
          header_lines =
            changelog_lines.select.with_index do |line, index|
              next true if line.start_with?("#", "!")
              next true if line.match?(/^v?\d\.\d/)
              next true if changelog_lines[index + 1]&.match?(/^[=-]+$/)
              false
            end

          versions = []
          header_lines.each do |line|
            cleaned_line = line.gsub(/^[^0-9]*/, "").gsub(/[\s,:].*/, "")
            next if cleaned_line.empty? || !version_class.correct?(cleaned_line)
            versions << version_class.new(cleaned_line)
          end

          versions
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
          case source.host
          when "github" then fetch_github_file_list
          when "bitbucket" then fetch_bitbucket_file_list
          when "gitlab" then fetch_gitlab_file_list
          else raise "Unexpected repo host '#{source.host}'"
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
              size: file.fetch("size", 0),
              html_url: "#{source.url}/src/master/#{file['path']}",
              download_url: "#{source.url}/raw/master/#{file['path']}"
            )
          end
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

        def version_class
          Utils.version_class_for_package_manager(dependency.package_manager)
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
# rubocop:enable Metrics/ClassLength
