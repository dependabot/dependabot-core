# typed: strict
# frozen_string_literal: true

require "excon"
require "sorbet-runtime"

require "dependabot/clients/github_with_retries"
require "dependabot/clients/gitlab_with_retries"
require "dependabot/clients/bitbucket_with_retries"
require "dependabot/shared_helpers"
require "dependabot/metadata_finders/base"

module Dependabot
  module MetadataFinders
    class Base
      # rubocop:disable Metrics/ClassLength
      class ChangelogFinder
        extend T::Sig

        require_relative "changelog_pruner"
        require_relative "commits_finder"

        # Earlier entries are preferred
        CHANGELOG_NAMES = T.let(
          %w(changelog news changes history release whatsnew releases).freeze,
          T::Array[String]
        )

        sig { returns(T.nilable(Dependabot::Source)) }
        attr_reader :source

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(T.nilable(String)) }
        attr_reader :suggested_changelog_url

        sig do
          params(
            source: T.nilable(Dependabot::Source),
            dependency: Dependabot::Dependency,
            credentials: T::Array[Dependabot::Credential],
            suggested_changelog_url: T.nilable(String)
          )
            .void
        end
        def initialize(source:, dependency:, credentials:,
                       suggested_changelog_url: nil)
          @source = source
          @dependency = dependency
          @credentials = credentials
          @suggested_changelog_url = suggested_changelog_url

          @new_version = T.let(nil, T.nilable(String))
          @changelog_from_suggested_url = T.let(nil, T.untyped)
        end

        sig { returns(T.nilable(String)) }
        def changelog_url
          changelog&.html_url
        end

        sig { returns(T.nilable(String)) }
        def changelog_text
          return unless full_changelog_text

          ChangelogPruner.new(
            dependency: dependency,
            changelog_text: full_changelog_text
          ).pruned_text
        end

        sig { returns(T.nilable(String)) }
        def upgrade_guide_url
          upgrade_guide&.html_url
        end

        sig { returns(T.nilable(String)) }
        def upgrade_guide_text
          return unless upgrade_guide

          @upgrade_guide_text ||= T.let(
            fetch_file_text(upgrade_guide),
            T.nilable(String)
          )
        end

        private

        # rubocop:disable Metrics/PerceivedComplexity
        sig { returns(T.untyped) }
        def changelog
          return unless changelog_from_suggested_url || source
          return if git_source? && !ref_changed?
          return changelog_from_suggested_url if changelog_from_suggested_url

          # If there is a changelog, and it includes the new version, return it
          if new_version && default_branch_changelog &&
             fetch_file_text(default_branch_changelog)&.include?(T.must(new_version))
            return default_branch_changelog
          end

          # Otherwise, look for a changelog at the tag for this version
          if new_version && relevant_tag_changelog &&
             fetch_file_text(relevant_tag_changelog)&.include?(T.must(new_version))
            return relevant_tag_changelog
          end

          # Fall back to the changelog (or nil) from the default branch
          default_branch_changelog
        end
        # rubocop:enable Metrics/PerceivedComplexity

        sig { returns(T.nilable(Sawyer::Resource)) }
        def changelog_from_suggested_url
          return @changelog_from_suggested_url unless @changelog_from_suggested_url.nil?
          return unless suggested_changelog_url

          # TODO: Support other providers
          suggested_source = Source.from_url(suggested_changelog_url)
          return unless suggested_source&.provider == "github"

          opts = { path: suggested_source&.directory, ref: suggested_source&.branch }.compact
          suggested_source_client = github_client_for_source(T.must(suggested_source))
          tmp_files = T.unsafe(suggested_source_client).contents(suggested_source&.repo, opts)

          filename = T.must(T.must(suggested_changelog_url).split("/").last).split("#").first

          # If the suggested source points to a specific directory
          # then we will receive a hash for just the changelog file
          if suggested_source&.directory && tmp_files[:name] == filename
            return @changelog_from_suggested_url = tmp_files
          end

          # Otherwise we will get back an array of hashes representing the files
          # in the root directory and we need to find the changelog
          @changelog_from_suggested_url =
            tmp_files.find { |f| f.name == filename }
        rescue Octokit::NotFound, Octokit::UnavailableForLegalReasons
          @changelog_from_suggested_url = nil
        end

        sig { returns(T.nilable(T.any(OpenStruct, Sawyer::Resource))) }
        def default_branch_changelog
          return unless source

          @default_branch_changelog ||=
            T.let(
              changelog_from_ref(nil),
              T.nilable(T.any(OpenStruct, Sawyer::Resource))
            )
        end

        sig { returns(T.nilable(T.any(OpenStruct, Sawyer::Resource))) }
        def relevant_tag_changelog
          return unless source
          return unless tag_for_new_version

          @relevant_tag_changelog ||=
            T.let(
              changelog_from_ref(tag_for_new_version),
              T.nilable(T.any(OpenStruct, Sawyer::Resource))
            )
        end

        sig { params(ref: T.nilable(String)).returns(T.nilable(T.any(OpenStruct, Sawyer::Resource))) }
        def changelog_from_ref(ref)
          files =
            dependency_file_list(ref)
            .select { |f| f.type == "file" }
            .reject { |f| f.name.end_with?(".sh") }
            .reject { |f| f.size > 1_000_000 }
            .reject { |f| f.size < 100 }

          select_best_changelog(files)
        end

        # rubocop:disable Metrics/PerceivedComplexity
        sig { params(files: T::Array[T.untyped]).returns(T.untyped) }
        def select_best_changelog(files)
          CHANGELOG_NAMES.each do |name|
            candidates = files.select { |f| f.name =~ /#{name}/i }
            file = candidates.first if candidates.one?
            file ||=
              candidates.find do |f|
                if fetch_file_text(f).nil?
                  candidates -= [f]
                  next
                end
                pruner = ChangelogPruner.new(
                  dependency: dependency,
                  changelog_text: fetch_file_text(f)
                )
                pruner.includes_new_version? ||
                  pruner.includes_previous_version?
              end
            file ||= candidates.max_by(&:size)
            return file if file
          end

          nil
        end
        # rubocop:enable Metrics/PerceivedComplexity

        sig { returns(T.nilable(String)) }
        def tag_for_new_version
          @tag_for_new_version ||=
            T.let(
              CommitsFinder.new(
                dependency: dependency,
                source: source,
                credentials: credentials
              ).new_tag,
              T.nilable(String)
            )
        end

        sig { returns(T.nilable(String)) }
        def full_changelog_text
          return unless changelog

          fetch_file_text(changelog)
        end

        sig { params(file: T.untyped).returns(T.nilable(String)) }
        def fetch_file_text(file)
          @file_text ||= T.let({}, T.nilable(T::Hash[String, T.untyped]))

          unless @file_text.key?(file.download_url)
            file_source = T.must(Source.from_url(file.html_url))
            @file_text[file.download_url] =
              case file_source.provider
              when "github" then fetch_github_file(file_source, file)
              when "gitlab" then fetch_gitlab_file(file)
              when "bitbucket" then fetch_bitbucket_file(file)
              when "azure" then fetch_azure_file(file)
              when "codecommit" then nil # TODO: git file from codecommit
              else raise "Unsupported provider '#{file_source.provider}'"
              end
          end

          return unless @file_text[file.download_url].valid_encoding?

          @file_text[file.download_url].rstrip
        end

        sig { params(file_source: Dependabot::Source, file: T.untyped).returns(String) }
        def fetch_github_file(file_source, file)
          # Hitting the download URL directly causes encoding problems
          raw_content = T.unsafe(github_client_for_source(file_source)).get(file.url).content
          Base64.decode64(raw_content).force_encoding("UTF-8").encode
        end

        sig { params(file: T.untyped).returns(String) }
        def fetch_gitlab_file(file)
          Excon.get(
            file.download_url,
            idempotent: true,
            **SharedHelpers.excon_defaults
          ).body.force_encoding("UTF-8").encode
        end

        sig { params(file: T.untyped).returns(String) }
        def fetch_bitbucket_file(file)
          T.unsafe(bitbucket_client).get(file.download_url).body
           .force_encoding("UTF-8").encode
        end

        sig { params(file: T.untyped).returns(String) }
        def fetch_azure_file(file)
          azure_client.get(file.download_url).body
                      .force_encoding("UTF-8").encode
        end

        sig { returns(T.untyped) }
        def upgrade_guide
          return unless source

          # Upgrade guide usually won't be relevant for bumping anything other
          # than the major version
          return unless major_version_upgrade?

          dependency_file_list
            .select { |f| f.type == "file" }
            .select { |f| f.name.casecmp("upgrade.md").zero? }
            .reject { |f| f.size > 1_000_000 }
            .max_by(&:size)
        end

        sig { params(ref: T.nilable(String)).returns(T.untyped) }
        def dependency_file_list(ref = nil)
          @dependency_file_list ||= T.let({}, T.nilable(T::Hash[T.nilable(String), T.untyped]))
          @dependency_file_list[ref] ||= fetch_dependency_file_list(ref)
        end

        sig { params(ref: T.nilable(String)).returns(T::Array[T.untyped,]) }
        def fetch_dependency_file_list(ref)
          case T.must(source).provider
          when "github" then fetch_github_file_list(ref)
          when "bitbucket" then fetch_bitbucket_file_list
          when "gitlab" then fetch_gitlab_file_list
          when "azure" then fetch_azure_file_list
          when "codecommit" then [] # TODO: Fetch Files from Codecommit
          else raise "Unexpected repo provider '#{T.must(source).provider}'"
          end
        end

        # rubocop:disable Metrics/AbcSize
        sig { params(ref: T.nilable(String)).returns(T::Array[T.untyped]) }
        def fetch_github_file_list(ref)
          files = []

          if T.must(source).directory
            opts = { path: T.must(source).directory, ref: ref }.compact
            tmp_files = T.unsafe(github_client).contents(T.must(source).repo, opts)
            files += tmp_files if tmp_files.is_a?(Array)
          end

          opts = { ref: ref }.compact
          files += T.unsafe(github_client).contents(T.must(source).repo, opts)

          files.uniq.each do |f|
            next unless f.type == "dir" && f.name.match?(/docs?/o)

            opts = { path: f.path, ref: ref }.compact
            files += T.unsafe(github_client).contents(T.must(source).repo, opts)
          end

          files
        rescue Octokit::NotFound, Octokit::UnavailableForLegalReasons
          []
        end
        # rubocop:enable Metrics/AbcSize

        sig { returns(T.untyped) }
        def fetch_bitbucket_file_list
          branch = default_bitbucket_branch
          T.unsafe(bitbucket_client).fetch_repo_contents(T.must(source).repo).map do |file|
            type = case file.fetch("type")
                   when "commit_file" then "file"
                   when "commit_directory" then "dir"
                   else file.fetch("type")
                   end
            OpenStruct.new(
              name: file.fetch("path").split("/").last,
              type: type,
              size: file.fetch("size", 100),
              html_url: "#{T.must(source).url}/src/#{branch}/#{file['path']}",
              download_url: "#{T.must(source).url}/raw/#{branch}/#{file['path']}"
            )
          end
        rescue Dependabot::Clients::Bitbucket::NotFound,
               Dependabot::Clients::Bitbucket::Unauthorized,
               Dependabot::Clients::Bitbucket::Forbidden
          []
        end

        sig { returns(T.untyped) }
        def fetch_gitlab_file_list
          branch = default_gitlab_branch
          T.unsafe(gitlab_client).repo_tree(T.must(source).repo).map do |file|
            type = case file.type
                   when "blob" then "file"
                   when "tree" then "dir"
                   else file.fetch("type")
                   end
            OpenStruct.new(
              name: file.name,
              type: type,
              size: 100, # GitLab doesn't return file size
              html_url: "#{T.must(source).url}/blob/#{branch}/#{file.path}",
              download_url: "#{T.must(source).url}/raw/#{branch}/#{file.path}"
            )
          end
        rescue Gitlab::Error::NotFound
          []
        end

        sig { returns(T.untyped) }
        def fetch_azure_file_list
          azure_client.fetch_repo_contents.map do |entry|
            type = case entry.fetch("gitObjectType")
                   when "blob" then "file"
                   when "tree" then "dir"
                   else entry.fetch("gitObjectType")
                   end

            OpenStruct.new(
              name: File.basename(entry.fetch("relativePath")),
              type: type,
              size: entry.fetch("size"),
              path: entry.fetch("relativePath"),
              html_url: "#{T.must(source).url}?path=/#{entry.fetch('relativePath')}",
              download_url: entry.fetch("url")
            )
          end
        rescue Dependabot::Clients::Azure::NotFound,
               Dependabot::Clients::Azure::Unauthorized,
               Dependabot::Clients::Azure::Forbidden
          []
        end

        sig { returns(T.nilable(String)) }
        def new_version
          return @new_version unless @new_version.nil?

          new_version = git_source? && new_ref ? new_ref : dependency.version
          @new_version = new_version&.gsub(/^v/, "")
        end

        sig { returns(T.nilable(String)) }
        def previous_ref
          previous_refs = dependency.previous_requirements&.filter_map do |r|
            r.dig(:source, "ref") || r.dig(:source, :ref)
          end&.uniq
          previous_refs&.first if previous_refs&.count == 1
        end

        sig { returns(T.nilable(String)) }
        def new_ref
          new_refs = dependency.requirements.filter_map do |r|
            r.dig(:source, "ref") || r.dig(:source, :ref)
          end.uniq
          new_refs.first if new_refs.count == 1
        end

        sig { returns(T::Boolean) }
        def ref_changed?
          # We could go from multiple previous refs (nil) to a single new ref
          previous_ref != new_ref
        end

        # TODO: Refactor me so that Composer doesn't need to be special cased
        sig { returns(T::Boolean) }
        def git_source?
          # Special case Composer, which uses git as a source but handles tags
          # internally
          return false if dependency.package_manager == "composer"

          requirements = dependency.requirements
          sources = requirements.map { |r| r.fetch(:source) }.uniq.compact
          return false if sources.empty?

          sources.all? { |s| s[:type] == "git" || s["type"] == "git" }
        end

        sig { returns(T::Boolean) }
        def major_version_upgrade?
          return false unless dependency.version&.match?(/^\d/)
          return false unless dependency.previous_version&.match?(/^\d/)

          T.must(dependency.version).split(".").first.to_i -
            T.must(dependency.previous_version).split(".").first.to_i >= 1
        end

        sig { returns(Dependabot::Clients::GitlabWithRetries) }
        def gitlab_client
          @gitlab_client ||=
            T.let(
              Dependabot::Clients::GitlabWithRetries.for_gitlab_dot_com(credentials: credentials),
              T.nilable(Dependabot::Clients::GitlabWithRetries)
            )
        end

        sig { returns(Dependabot::Clients::GithubWithRetries) }
        def github_client
          @github_client ||=
            T.let(
              Dependabot::Clients::GithubWithRetries.for_source(source: T.must(source), credentials: credentials),
              T.nilable(Dependabot::Clients::GithubWithRetries)
            )
        end

        sig { returns(Dependabot::Clients::Azure) }
        def azure_client
          @azure_client ||=
            T.let(
              Dependabot::Clients::Azure.for_source(source: T.must(source), credentials: credentials),
              T.nilable(Dependabot::Clients::Azure)
            )
        end

        sig { params(client_source: Dependabot::Source).returns(Dependabot::Clients::GithubWithRetries) }
        def github_client_for_source(client_source)
          return github_client if client_source == source

          Dependabot::Clients::GithubWithRetries.for_source(source: client_source, credentials: credentials)
        end

        sig { returns(Dependabot::Clients::BitbucketWithRetries) }
        def bitbucket_client
          @bitbucket_client ||=
            T.let(
              Dependabot::Clients::BitbucketWithRetries.for_bitbucket_dot_org(credentials: credentials),
              T.nilable(Dependabot::Clients::BitbucketWithRetries)
            )
        end

        sig { returns(String) }
        def default_bitbucket_branch
          @default_bitbucket_branch ||=
            T.let(
              T.unsafe(bitbucket_client).fetch_default_branch(T.must(source).repo),
              T.nilable(String)
            )
        end

        sig { returns(String) }
        def default_gitlab_branch
          @default_gitlab_branch ||=
            T.let(
              gitlab_client.fetch_default_branch(T.must(source).repo),
              T.nilable(String)
            )
        end
      end
      # rubocop:enable Metrics/ClassLength
    end
  end
end
