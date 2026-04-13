# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/nix/update_checker"
require "dependabot/git_metadata_fetcher"
require "dependabot/git_ref"

module Dependabot
  module Nix
    class UpdateChecker
      # Detects versioned branch naming patterns (e.g. nixos-24.11, release-24.11)
      # and finds the latest branch matching the same prefix.
      class VersionedBranchFinder
        extend T::Sig

        # Matches branch names with a YY.MM version segment and optional suffix.
        # Captures: prefix (including separator), version, and optional suffix.
        # Examples: "nixos-24.11" => prefix="nixos-", version="24.11", suffix=nil
        #           "nixos-24.11-small" => prefix="nixos-", version="24.11", suffix="-small"
        #           "release-24.11-aarch64" => prefix="release-", version="24.11", suffix="-aarch64"
        VERSIONED_BRANCH_PATTERN = /\A(.+[.\-_])(\d{2}\.\d{2})(-[a-zA-Z0-9]+)?\z/
        private_constant :VERSIONED_BRANCH_PATTERN

        sig do
          params(
            current_ref: String,
            dependency: Dependabot::Dependency,
            credentials: T::Array[Dependabot::Credential]
          ).void
        end
        def initialize(current_ref:, dependency:, credentials:)
          @current_ref = current_ref
          @dependency = dependency
          @credentials = credentials
        end

        # Returns true if the current ref looks like a versioned branch.
        sig { returns(T::Boolean) }
        def versioned_branch?
          !branch_version_match.nil?
        end

        # Returns the latest versioned branch info or nil if no newer branch exists.
        # Returns { branch: "nixos-25.05", commit_sha: "abc123" } or nil.
        sig { returns(T.nilable(T::Hash[Symbol, String])) }
        def latest_versioned_branch
          match = branch_version_match
          return unless match

          prefix = match[1]
          current_version = parse_version(T.must(match[2]))
          return unless current_version

          suffix = match[3] # nil if no suffix, e.g. "-small" if present
          find_latest_branch(T.must(prefix), current_version, suffix)
        end

        private

        sig { returns(String) }
        attr_reader :current_ref

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(T.nilable(MatchData)) }
        def branch_version_match
          @branch_version_match ||= T.let(
            VERSIONED_BRANCH_PATTERN.match(current_ref),
            T.nilable(MatchData)
          )
        end

        sig do
          params(
            prefix: String,
            current_version: T::Array[Integer],
            suffix: T.nilable(String)
          ).returns(T.nilable(T::Hash[Symbol, String]))
        end
        def find_latest_branch(prefix, current_version, suffix)
          candidates = remote_branches.filter_map do |ref|
            branch_match = VERSIONED_BRANCH_PATTERN.match(ref.name)
            next unless branch_match
            next unless branch_match[1] == prefix
            next unless branch_match[3] == suffix

            version = parse_version(T.must(branch_match[2]))
            next unless version
            next unless (version <=> current_version) == 1

            { branch: ref.name, commit_sha: ref.commit_sha, version: version }
          end

          latest = candidates.max_by { |c| c[:version] }
          return unless latest

          { branch: latest[:branch].to_s, commit_sha: latest[:commit_sha].to_s }
        end

        # Parses "YY.MM" into [year, month] for comparison.
        sig { params(version_str: String).returns(T.nilable(T::Array[Integer])) }
        def parse_version(version_str)
          parts = version_str.split(".")
          return unless parts.length == 2

          year = Integer(T.must(parts[0]), 10)
          month = Integer(T.must(parts[1]), 10)
          return unless month.between?(1, 12)

          [year, month]
        rescue ArgumentError
          nil
        end

        sig { returns(T::Array[Dependabot::GitRef]) }
        def remote_branches
          @remote_branches ||= T.let(
            git_metadata_fetcher.refs_for_upload_pack.select do |ref|
              ref.ref_type == Dependabot::RefType::Head
            end,
            T.nilable(T::Array[Dependabot::GitRef])
          )
        end

        sig { returns(Dependabot::GitMetadataFetcher) }
        def git_metadata_fetcher
          @git_metadata_fetcher ||= T.let(
            Dependabot::GitMetadataFetcher.new(
              url: dependency.source_details&.fetch(:url, nil),
              credentials: credentials
            ),
            T.nilable(Dependabot::GitMetadataFetcher)
          )
        end
      end
    end
  end
end
