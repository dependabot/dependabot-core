# typed: strict
# frozen_string_literal: true

require "json"
require "time"
require "uri"
require "sorbet-runtime"
require "dependabot/nix"
require "dependabot/package/package_release"
require "dependabot/package/package_details"
require "dependabot/git_commit_checker"
require "dependabot/git_metadata_fetcher"
require "dependabot/clients/github_with_retries"

module Dependabot
  module Nix
    module Package
      class PackageDetailsFetcher
        extend T::Sig

        sig do
          params(
            dependency: Dependabot::Dependency,
            credentials: T::Array[Dependabot::Credential]
          ).void
        end
        def initialize(dependency:, credentials:)
          @dependency = dependency
          @credentials = credentials
        end

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[T.untyped]) }
        attr_reader :credentials

        sig { returns(T.nilable(T::Array[Dependabot::Package::PackageRelease])) }
        def available_versions
          versions_metadata = fetch_branch_tip_history || fetch_tags_and_release_date

          versions_metadata = fetch_latest_tag_info if versions_metadata.empty?

          pseudo_version = versions_metadata.length + 1

          versions_metadata.flat_map do |version_details|
            pseudo_version -= 1
            tag = version_details[:tag]
            release_date = version_details[:release_date]

            Dependabot::Package::PackageRelease.new(
              version: Nix::Version.new("0.0.0-0.#{pseudo_version}"),
              tag: tag,
              released_at: release_date ? Time.parse(release_date) : nil
            )
          rescue ArgumentError
            Dependabot::Package::PackageRelease.new(
              version: Nix::Version.new("0.0.0-0.#{pseudo_version}"),
              tag: tag
            )
          end
        end

        private

        TARGET_COMMITS_TO_FETCH = 500
        ACTIVITY_TYPES = "push,force_push"
        SHA_REGEX = /\A[0-9a-f]{40}\z/
        private_constant :TARGET_COMMITS_TO_FETCH, :ACTIVITY_TYPES, :SHA_REGEX

        # Fetch branch-tip history via GitHub's Repo Activity API. Each entry's
        # `after` SHA was once the actual branch tip — for `nixpkgs` channels
        # that means it was Hydra-evaluated and is cache-backed. The /commits
        # endpoint, by contrast, returns intermediate commits that were never
        # branch tips and may not be cached.
        #
        # Returns nil when the activity API isn't usable (non-GitHub host,
        # SHA-pinned ref, missing ref, HTTP error). Callers should fall back to
        # the existing /commits walker in that case.
        sig { returns(T.nilable(T::Array[T::Hash[Symbol, T.untyped]])) }
        def fetch_branch_tip_history
          url = source_url
          ref = branch_ref
          return nil unless use_activity_api?(url, ref)

          Dependabot.logger.info("Fetching branch-tip history for Nix flake input: #{dependency.name}")
          path = "/repos/#{github_repo_path(T.must(url))}/activity"
          entries = T.unsafe(github_client).get(
            path,
            ref: "refs/heads/#{T.must(ref)}",
            activity_type: ACTIVITY_TYPES,
            per_page: 100
          )
          return nil unless entries.is_a?(Array) && entries.any?

          entries.map { |e| { tag: e[:after], release_date: format_timestamp(e[:timestamp]) } }
        rescue Octokit::Error => e
          Dependabot.logger.info(
            "Repo Activity API failed for #{dependency.name} (#{e.class}: #{e.message}), " \
            "falling back to commits API"
          )
          nil
        rescue StandardError => e
          Dependabot.logger.error("Error fetching branch-tip history: #{e.message}")
          nil
        end

        sig { params(timestamp: T.untyped).returns(T.nilable(String)) }
        def format_timestamp(timestamp)
          return nil if timestamp.nil?
          return timestamp.iso8601 if timestamp.respond_to?(:iso8601)

          timestamp.to_s
        end

        sig { params(url: T.nilable(String), ref: T.nilable(String)).returns(T::Boolean) }
        def use_activity_api?(url, ref)
          return false unless url && ref
          return false if ref.match?(SHA_REGEX)

          host = URI.parse(url).host
          host == "github.com"
        rescue URI::InvalidURIError
          false
        end

        sig { params(url: String).returns(String) }
        def github_repo_path(url)
          T.must(URI.parse(url).path)
           .delete_prefix("/")
           .delete_suffix("/")
           .delete_suffix(".git")
        end

        sig { returns(T.nilable(String)) }
        def source_url
          dependency.source_details(allowed_types: ["git"])&.fetch(:url, nil)
        end

        sig { returns(T.nilable(String)) }
        def branch_ref
          dependency.source_details(allowed_types: ["git"])&.fetch(:ref, nil)
        end

        sig { returns(Dependabot::Clients::GithubWithRetries) }
        def github_client
          @github_client ||= T.let(
            Dependabot::Clients::GithubWithRetries.for_github_dot_com(credentials: credentials),
            T.nilable(Dependabot::Clients::GithubWithRetries)
          )
        end

        sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        def fetch_latest_tag_info
          client = build_client
          head = client.head_commit_for_current_branch
          return [] unless head

          [{ tag: head }]
        end

        sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        def fetch_tags_and_release_date
          parsed_results = T.let([], T::Array[T::Hash[Symbol, T.untyped]])

          begin
            Dependabot.logger.info("Fetching release info for Nix flake input: #{dependency.name}")
            client = build_client

            sha = T.let(nil, T.nilable(String))
            catch :found do
              while parsed_results.length < TARGET_COMMITS_TO_FETCH
                commits = get_commits(client, sha)
                break if commits.empty?

                commits.each do |commit|
                  sha = commit["sha"]
                  parsed_results << {
                    tag: sha,
                    release_date: commit.dig("commit", "committer", "date")
                  }
                  throw :found if sha == dependency.version
                end
                break if commits.length < Dependabot::GitMetadataFetcher::MAX_COMMITS_PER_PAGE
              end
            end
            parsed_results
          rescue StandardError => e
            Dependabot.logger.error("Error while fetching package info for nix flake input: #{e.message}")
            parsed_results
          end
        end

        sig { returns(Dependabot::GitCommitChecker) }
        def build_client
          Dependabot::GitCommitChecker.new(
            dependency: dependency,
            credentials: credentials
          )
        end

        sig do
          params(
            client: Dependabot::GitCommitChecker,
            sha: T.nilable(String)
          ).returns(T::Array[T::Hash[String, T.untyped]])
        end
        def get_commits(client, sha)
          response = sha.nil? ? client.ref_details_for_pinned_ref : client.ref_details(sha)

          unless response.status == 200
            Dependabot.logger.error(
              "Error while fetching details for #{dependency.name}: #{response.body}"
            )
          end

          return [] unless response.status == 200

          commits = JSON.parse(response.body)
          sha.nil? || commits.empty? ? commits : commits[1..]
        rescue StandardError => e
          Dependabot.logger.error("Error fetching commits: #{e.message}")
          []
        end
      end
    end
  end
end
