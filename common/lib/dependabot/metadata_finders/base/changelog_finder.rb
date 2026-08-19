# typed: strong
# frozen_string_literal: true

require "excon"
require "sorbet-runtime"

require "dependabot/clients/github_with_retries"
require "dependabot/clients/gitlab_with_retries"
require "dependabot/clients/bitbucket_with_retries"
require "dependabot/errors"
require "dependabot/shared_helpers"
require "dependabot/metadata_finders/base"

module Dependabot
  module MetadataFinders
    class Base
      class ChangelogFile < T::ImmutableStruct
        const :name, String
        const :type, String
        const :size, Integer
        const :html_url, String
        const :download_url, String
        const :path, T.nilable(String), default: nil
        const :api_url, T.nilable(String), default: nil
      end

      # rubocop:disable Metrics/ClassLength
      class ChangelogFinder
        extend T::Sig

        require_relative "changelog_pruner"
        require_relative "commits_finder"

        # Earlier entries are preferred
        CHANGELOG_NAMES = %w(changelog news changes history release whatsnew releases).freeze
        CHANGELOG_FILE_TYPES = %w(file dir).freeze

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
        def initialize(
          source:,
          dependency:,
          credentials:,
          suggested_changelog_url: nil
        )
          @source = source
          @dependency = dependency
          @credentials = credentials
          @suggested_changelog_url = suggested_changelog_url
          # strip fragment from URL, if present
          @suggested_changelog_url = @suggested_changelog_url&.split("#")&.first

          @new_version = T.let(nil, T.nilable(String))
          @changelog_from_suggested_url = T.let(nil, T.nilable(ChangelogFile))
          @file_text = T.let({}, T::Hash[String, T.nilable(String)])
          @dependency_file_list = T.let({}, T::Hash[T.nilable(String), T::Array[ChangelogFile]])
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
          guide = upgrade_guide
          return unless guide

          @upgrade_guide_text ||= T.let(
            fetch_file_text(guide),
            T.nilable(String)
          )
        end

        private

        # rubocop:disable Metrics/PerceivedComplexity
        sig { returns(T.nilable(ChangelogFile)) }
        def changelog
          return unless changelog_from_suggested_url || source
          return if git_source? && !ref_changed?
          return changelog_from_suggested_url if changelog_from_suggested_url

          # If there is a changelog, and it includes the new version, return it
          default_changelog = default_branch_changelog
          if new_version && default_changelog &&
             fetch_file_text(default_changelog)&.include?(T.must(new_version))
            return default_changelog
          end

          # Otherwise, look for a changelog at the tag for this version
          tag_changelog = relevant_tag_changelog
          if new_version && tag_changelog &&
             fetch_file_text(tag_changelog)&.include?(T.must(new_version))
            return tag_changelog
          end

          # Fall back to the changelog (or nil) from the default branch
          default_branch_changelog
        end
        # rubocop:enable Metrics/PerceivedComplexity

        sig { returns(T.nilable(ChangelogFile)) }
        def changelog_from_suggested_url
          return @changelog_from_suggested_url unless @changelog_from_suggested_url.nil?
          return unless suggested_changelog_url

          # TODO: Support other providers
          suggested_source = Source.from_url(suggested_changelog_url)
          return unless suggested_source&.provider == "github"

          opts = { path: suggested_source&.directory, ref: suggested_source&.branch }.compact
          suggested_source_client = github_client_for_source(T.must(suggested_source))
          response = suggested_source_client.contents(T.must(suggested_source).repo, opts)
          tmp_files = github_changelog_files(response, source_url: T.must(suggested_source).url)

          filename = T.must(T.must(suggested_changelog_url).split("/").last)
          @changelog_from_suggested_url = tmp_files.find { |f| f.name == filename }
        rescue Octokit::NotFound, Octokit::UnavailableForLegalReasons
          @changelog_from_suggested_url = nil
        end

        sig { returns(T.nilable(ChangelogFile)) }
        def default_branch_changelog
          return unless source

          @default_branch_changelog ||=
            T.let(
              changelog_from_ref(nil),
              T.nilable(ChangelogFile)
            )
        end

        sig { returns(T.nilable(ChangelogFile)) }
        def relevant_tag_changelog
          return unless source
          return unless tag_for_new_version

          @relevant_tag_changelog ||=
            T.let(
              changelog_from_ref(tag_for_new_version),
              T.nilable(ChangelogFile)
            )
        end

        sig { params(ref: T.nilable(String)).returns(T.nilable(ChangelogFile)) }
        def changelog_from_ref(ref)
          files =
            dependency_file_list(ref)
            .select { |f| f.type == "file" }
            .reject { |f| f.name.end_with?(".sh") }
            # JSON files are machine-readable, not useful as changelogs
            .reject { |f| f.name.end_with?(".json") }
            .reject { |f| f.size > 1_000_000 }
            .reject { |f| f.size < 100 }

          select_best_changelog(files)
        end

        # rubocop:disable Metrics/PerceivedComplexity
        sig { params(files: T::Array[ChangelogFile]).returns(T.nilable(ChangelogFile)) }
        def select_best_changelog(files)
          CHANGELOG_NAMES.each do |name|
            candidates = files.select { |f| f.name =~ /\A#{name}/i }
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
          selected_changelog = changelog
          return unless selected_changelog

          fetch_file_text(selected_changelog)
        end

        sig { params(file: ChangelogFile).returns(T.nilable(String)) }
        def fetch_file_text(file)
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

          text = @file_text[file.download_url]
          return unless text&.valid_encoding?

          text.rstrip
        end

        sig { params(file_source: Dependabot::Source, file: ChangelogFile).returns(String) }
        def fetch_github_file(file_source, file)
          # Hitting the download URL directly causes encoding problems
          response = github_client_for_source(file_source).get(T.must(file.api_url))
          raise_bad_metadata_response("GitHub", "file response must be an object", source_url: file_source.url) unless
            response.is_a?(Sawyer::Resource)

          raw_content = sawyer_string(response, :content, source_url: file_source.url)
          Base64.decode64(raw_content).force_encoding("UTF-8").encode
        end

        sig { params(file: ChangelogFile).returns(String) }
        def fetch_gitlab_file(file)
          Excon.get(
            file.download_url,
            idempotent: true,
            **SharedHelpers.excon_defaults
          ).body.force_encoding("UTF-8").encode
        end

        sig { params(file: ChangelogFile).returns(String) }
        def fetch_bitbucket_file(file)
          bitbucket_client.get(file.download_url).body
                          .force_encoding("UTF-8").encode
        end

        sig { params(file: ChangelogFile).returns(String) }
        def fetch_azure_file(file)
          azure_client.get(file.download_url).body
                      .force_encoding("UTF-8").encode
        end

        sig { returns(T.nilable(ChangelogFile)) }
        def upgrade_guide
          return unless source

          # Upgrade guide usually won't be relevant for bumping anything other
          # than the major version
          return unless major_version_upgrade?

          dependency_file_list
            .select { |f| f.type == "file" }
            .select { |f| f.name.casecmp?("upgrade.md") }
            .reject { |f| f.size > 1_000_000 }
            .max_by(&:size)
        end

        sig { params(ref: T.nilable(String)).returns(T::Array[ChangelogFile]) }
        def dependency_file_list(ref = nil)
          @dependency_file_list[ref] ||= fetch_dependency_file_list(ref)
        end

        sig { params(ref: T.nilable(String)).returns(T::Array[ChangelogFile]) }
        def fetch_dependency_file_list(ref)
          case T.must(source).provider
          when "github" then fetch_github_file_list(ref)
          when "bitbucket" then fetch_bitbucket_file_list
          when "gitlab" then fetch_gitlab_file_list
          when "azure" then fetch_azure_file_list
          when "codecommit" then [] # TODO: Fetch Files from Codecommit
          when "example" then []
          else raise "Unexpected repo provider '#{T.must(source).provider}'"
          end
        end

        sig { params(ref: T.nilable(String)).returns(T::Array[ChangelogFile]) }
        def fetch_github_file_list(ref)
          files = T.let([], T::Array[ChangelogFile])

          directory = T.must(source).directory
          if directory
            options = { path: directory, ref: ref }.compact
            response = github_client.contents(T.must(source).repo, options)
            files.concat(github_changelog_files(response, source_url: T.must(source).url)) if response.is_a?(Array)
          end
          files.concat(github_files_at(path: nil, ref: ref))

          files.uniq.each do |f|
            next unless f.type == "dir" && f.name.match?(/docs?/o)

            files.concat(github_files_at(path: f.path, ref: ref))
          end

          files
        rescue Octokit::NotFound, Octokit::UnavailableForLegalReasons
          []
        end

        sig { params(path: T.nilable(String), ref: T.nilable(String)).returns(T::Array[ChangelogFile]) }
        def github_files_at(path:, ref:)
          options = { path: path, ref: ref }.compact
          github_changelog_files(
            github_client.contents(T.must(source).repo, options),
            source_url: T.must(source).url
          )
        end

        sig { returns(T::Array[ChangelogFile]) }
        def fetch_bitbucket_file_list
          branch = default_bitbucket_branch
          bitbucket_client.fetch_repo_contents(T.must(source).repo).map do |file|
            object_type = object_string(file, "type", "Bitbucket")
            path = object_string(file, "path", "Bitbucket")
            type = case object_type
                   when "commit_file" then "file"
                   when "commit_directory" then "dir"
                   else object_type
                   end
            ChangelogFile.new(
              name: T.must(path.split("/").last),
              type: type,
              size: object_integer(file, "size", "Bitbucket", default: 100),
              html_url: "#{T.must(source).url}/src/#{branch}/#{path}",
              download_url: "#{T.must(source).url}/raw/#{branch}/#{path}"
            )
          end
        rescue Dependabot::Clients::Bitbucket::NotFound,
               Dependabot::Clients::Bitbucket::Unauthorized,
               Dependabot::Clients::Bitbucket::Forbidden
          []
        end

        sig { returns(T::Array[ChangelogFile]) }
        def fetch_gitlab_file_list
          branch = default_gitlab_branch
          gitlab_client.repo_tree(T.must(source).repo).map do |file|
            object_type = gitlab_string(file, "type")
            type = case object_type
                   when "blob" then "file"
                   when "tree" then "dir"
                   else object_type
                   end
            path = gitlab_string(file, "path")
            ChangelogFile.new(
              name: gitlab_string(file, "name"),
              type: type,
              size: 100, # GitLab doesn't return file size
              html_url: "#{T.must(source).url}/blob/#{branch}/#{path}",
              download_url: "#{T.must(source).url}/raw/#{branch}/#{path}",
              path: path
            )
          end
        rescue Gitlab::Error::NotFound
          []
        end

        sig { returns(T::Array[ChangelogFile]) }
        def fetch_azure_file_list
          azure_client.fetch_repo_contents.map do |entry|
            object_type = object_string(entry, "gitObjectType", "Azure")
            relative_path = object_string(entry, "relativePath", "Azure")
            type = case object_type
                   when "blob" then "file"
                   when "tree" then "dir"
                   else object_type
                   end

            ChangelogFile.new(
              name: File.basename(relative_path),
              type: type,
              size: object_integer(entry, "size", "Azure"),
              path: relative_path,
              html_url: "#{T.must(source).url}?path=/#{relative_path}",
              download_url: object_string(entry, "url", "Azure")
            )
          end
        rescue Dependabot::Clients::Azure::NotFound,
               Dependabot::Clients::Azure::Unauthorized,
               Dependabot::Clients::Azure::Forbidden
          []
        end

        sig do
          params(
            response: T.any(Sawyer::Resource, T::Array[Sawyer::Resource]),
            source_url: String
          )
            .returns(T::Array[ChangelogFile])
        end
        def github_changelog_files(response, source_url:)
          resources = response.is_a?(Array) ? response : [response]
          resources.filter_map do |resource|
            type = sawyer_string(resource, :type, source_url: source_url)
            next unless CHANGELOG_FILE_TYPES.include?(type)

            api_url = sawyer_string(resource, :url, source_url: source_url)
            ChangelogFile.new(
              name: sawyer_string(resource, :name, source_url: source_url),
              type: type,
              size: sawyer_optional_integer(resource, :size, source_url: source_url) || 0,
              html_url: sawyer_string(resource, :html_url, source_url: source_url),
              download_url: sawyer_optional_string(resource, :download_url, source_url: source_url) || api_url,
              path: sawyer_optional_string(resource, :path, source_url: source_url),
              api_url: api_url
            )
          end
        end

        sig { params(resource: Sawyer::Resource, key: Symbol, source_url: String).returns(String) }
        def sawyer_string(resource, key, source_url:)
          value = T.cast(resource[key], Object)
          return value if value.is_a?(String)

          raise_bad_metadata_response("GitHub", "#{key} must be a string", source_url: source_url)
        end

        sig do
          params(resource: Sawyer::Resource, key: Symbol, source_url: String)
            .returns(T.nilable(String))
        end
        def sawyer_optional_string(resource, key, source_url:)
          value = T.cast(resource[key], Object)
          return if value.nil?
          return value if value.is_a?(String)

          raise_bad_metadata_response("GitHub", "#{key} must be a string or nil", source_url: source_url)
        end

        sig do
          params(resource: Sawyer::Resource, key: Symbol, source_url: String)
            .returns(T.nilable(Integer))
        end
        def sawyer_optional_integer(resource, key, source_url:)
          value = T.cast(resource[key], Object)
          return if value.nil?
          return value if value.is_a?(Integer)

          raise_bad_metadata_response("GitHub", "#{key} must be an integer or nil", source_url: source_url)
        end

        sig { params(resource: Gitlab::ObjectifiedHash, key: String).returns(String) }
        def gitlab_string(resource, key)
          value = T.cast(resource[key], Object)
          return value if value.is_a?(String)

          raise_bad_metadata_response("GitLab", "#{key} must be a string")
        end

        sig do
          params(object: T::Hash[String, Object], key: String, provider: String)
            .returns(String)
        end
        def object_string(object, key, provider)
          value = object[key]
          return value if value.is_a?(String)

          raise_bad_metadata_response(provider, "#{key} must be a string")
        end

        sig do
          params(
            object: T::Hash[String, Object],
            key: String,
            provider: String,
            default: T.nilable(Integer)
          ).returns(Integer)
        end
        def object_integer(object, key, provider, default: nil)
          value = object[key]
          return default if value.nil? && default
          return value if value.is_a?(Integer)

          raise_bad_metadata_response(provider, "#{key} must be an integer")
        end

        sig do
          params(
            provider: String,
            message: String,
            source_url: T.nilable(String)
          ).returns(T.noreturn)
        end
        def raise_bad_metadata_response(provider, message, source_url: nil)
          raise Dependabot::PrivateSourceBadResponse.new(
            source_url || T.must(source).url,
            "Malformed #{provider} metadata response: #{message}"
          )
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
            r.source_string("ref")
          end&.uniq
          previous_refs.first if previous_refs&.one?
        end

        sig { returns(T.nilable(String)) }
        def new_ref
          new_refs = dependency.requirements.filter_map do |r|
            r.source_string("ref")
          end.uniq
          new_refs.first if new_refs.one?
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
          sources = requirements.map(&:source_hash).uniq.compact
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
              bitbucket_client.fetch_default_branch(T.must(source).repo),
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
