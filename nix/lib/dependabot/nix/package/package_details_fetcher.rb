# typed: strong
# frozen_string_literal: true

require "json"
require "uri"
require "sorbet-runtime"
require "dependabot/nix"
require "dependabot/nix/package/revision_candidate"
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

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(T::Array[Dependabot::Package::PackageRelease]) }
        def available_versions
          versions_metadata = fetch_branch_tip_history || fetch_tags_and_release_date

          versions_metadata = fetch_latest_tag_info if versions_metadata.empty?

          versions_metadata.each_with_index.map do |candidate, index|
            Dependabot::Package::PackageRelease.new(
              version: Nix::Version.new("0.0.0-0.#{versions_metadata.length - index}"),
              tag: candidate.revision,
              released_at: candidate.released_at
            )
          end
        end

        private

        TARGET_COMMITS_TO_FETCH = 500
        ACTIVITY_TYPES = "push,force_push"
        SHA_REGEX = /\A[0-9a-f]{40}\z/
        NULL_SHA = "0000000000000000000000000000000000000000"
        # Heuristic for refs that look like a tag/version rather than a branch
        # (e.g. `v1.2.3`, `1.2`, `2024.01`). Branch names like `nixos-25.05`
        # don't match because they don't start with a digit or `v<digit>`.
        TAG_LIKE_REF_REGEX = /\Av?\d+\./
        private_constant :TARGET_COMMITS_TO_FETCH, :ACTIVITY_TYPES, :SHA_REGEX, :NULL_SHA, :TAG_LIKE_REF_REGEX

        # Fetch branch-tip history via GitHub's Repo Activity API. Each entry's
        # `after` SHA was once the actual branch tip — for `nixpkgs` channels
        # that means it was Hydra-evaluated and is cache-backed. The /commits
        # endpoint, by contrast, returns intermediate commits that were never
        # branch tips and may not be cached.
        #
        # The `activity_type` filter does not narrow the response to pushes, so it
        # also holds `branch_creation` and `branch_deletion` entries. A deletion
        # reports the null SHA as its `after`, which is not a revision anyone can
        # fetch. When the newest entry is a deletion the branch no longer exists
        # and has no releases; an older deletion, followed by the branch being
        # created again, is skipped.
        #
        # Returns nil when the activity API isn't usable (non-GitHub host,
        # SHA-pinned ref, missing ref, HTTP error). Callers should fall back to
        # the existing /commits walker in that case.
        sig { returns(T.nilable(T::Array[RevisionCandidate])) }
        def fetch_branch_tip_history
          url = source_url
          ref = branch_ref
          return nil unless use_activity_api?(url, ref)

          Dependabot.logger.info("Fetching branch-tip history for Nix flake input: #{dependency.name}")
          entries = fetch_activity_entries(T.must(url), T.must(ref))
          return nil unless entries.any?

          if branch_deletion?(T.must(entries.first))
            Dependabot.logger.info("Branch #{ref} of #{url} no longer exists, so #{dependency.name} has no releases")
            return []
          end

          trim_entries_to_locked_sha(entries.reject { |entry| branch_deletion?(entry) })
        rescue Dependabot::PrivateSourceBadResponse
          raise
        rescue Octokit::Error => e
          Dependabot.logger.info(
            "Repo Activity API failed for #{dependency.name} (#{e.class}: #{e.message}), " \
            "falling back to commits API"
          )
          nil
        rescue StandardError => e
          Dependabot.logger.error(
            "Error fetching branch-tip history for #{dependency.name} " \
            "(#{e.class}: #{e.message})"
          )
          nil
        end

        sig { params(url: String, ref: String).returns(T::Array[RevisionCandidate]) }
        def fetch_activity_entries(url, ref)
          response = github_client.get(
            "/repos/#{github_repo_path(url)}/activity",
            ref: "refs/heads/#{ref}",
            activity_type: ACTIVITY_TYPES,
            per_page: 100
          )
          unless response.is_a?(Array)
            raise Dependabot::PrivateSourceBadResponse.new(url, "Malformed Nix activity response: expected an array")
          end

          response.map { |entry| RevisionCandidate.from_activity(entry, source: url) }
        end

        # Trim to entries up to and including the currently locked SHA, stopping
        # once that SHA is reached so we don't introduce candidates older than
        # `dependency.version`.
        sig { params(entries: T::Array[RevisionCandidate]).returns(T::Array[RevisionCandidate]) }
        def trim_entries_to_locked_sha(entries)
          locked = dependency.version
          result = T.let([], T::Array[RevisionCandidate])
          entries.each do |entry|
            result << entry

            next unless locked
            break if entry.revision == locked

            if entry.previous_revision == locked
              result << RevisionCandidate.new(revision: locked) unless result.last&.revision == locked
              break
            end
          end
          result
        end

        sig { params(entry: RevisionCandidate).returns(T::Boolean) }
        def branch_deletion?(entry)
          entry.revision == NULL_SHA
        end

        sig { params(url: T.nilable(String), ref: T.nilable(String)).returns(T::Boolean) }
        def use_activity_api?(url, ref)
          return false unless url && ref
          return false if ref.match?(SHA_REGEX)
          return false if ref.match?(TAG_LIKE_REF_REGEX)

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
          dependency.source_string("url", allowed_types: ["git"])
        end

        sig { returns(T.nilable(String)) }
        def branch_ref
          dependency.source_string("ref", allowed_types: ["git"])
        end

        sig { returns(Dependabot::Clients::GithubWithRetries) }
        def github_client
          @github_client ||= T.let(
            Dependabot::Clients::GithubWithRetries.for_github_dot_com(credentials: credentials),
            T.nilable(Dependabot::Clients::GithubWithRetries)
          )
        end

        sig { returns(T::Array[RevisionCandidate]) }
        def fetch_latest_tag_info
          client = build_client
          head = client.head_commit_for_current_branch
          return [] unless head

          [RevisionCandidate.new(revision: head)]
        end

        sig { returns(T::Array[RevisionCandidate]) }
        def fetch_tags_and_release_date
          parsed_results = T.let([], T::Array[RevisionCandidate])

          begin
            Dependabot.logger.info("Fetching release info for Nix flake input: #{dependency.name}")
            client = build_client

            sha = T.let(nil, T.nilable(String))
            catch :found do
              while parsed_results.length < TARGET_COMMITS_TO_FETCH
                commits = get_commits(client, sha)
                break if commits.empty?

                commits.each do |commit|
                  sha = commit.revision
                  parsed_results << commit
                  throw :found if sha == dependency.version
                end
                break if commits.length < Dependabot::GitMetadataFetcher::MAX_COMMITS_PER_PAGE
              end
            end
            parsed_results
          rescue Dependabot::PrivateSourceBadResponse
            raise
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
          ).returns(T::Array[RevisionCandidate])
        end
        def get_commits(client, sha)
          response = sha.nil? ? client.ref_details_for_pinned_ref : client.ref_details(sha)

          unless response.status == 200
            Dependabot.logger.error(
              "Error while fetching details for #{dependency.name}: #{response.body}"
            )
            return []
          end

          parse_commits(response.body, skip_first: !sha.nil?)
        rescue Dependabot::PrivateSourceBadResponse
          raise
        rescue StandardError => e
          Dependabot.logger.error("Error fetching commits: #{e.message}")
          []
        end

        sig { params(body: String, skip_first: T::Boolean).returns(T::Array[RevisionCandidate]) }
        def parse_commits(body, skip_first:)
          source = source_url || dependency.name
          values = T.cast(JSON.parse(body), Object)
          unless values.is_a?(Array)
            raise Dependabot::PrivateSourceBadResponse.new(
              source, "Malformed Nix commit response: expected an array"
            )
          end

          commits = T.let([], T::Array[RevisionCandidate])
          values.drop(skip_first ? 1 : 0).each do |value|
            candidate = RevisionCandidate.from_commit(T.cast(value, Object), source: source)
            commits << candidate
            break if candidate.revision == dependency.version
          end
          commits
        rescue JSON::ParserError
          raise Dependabot::PrivateSourceBadResponse.new(
            source_url || dependency.name, "Malformed Nix commit response: expected valid JSON"
          )
        end
      end
    end
  end
end
