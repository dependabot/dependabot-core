# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/nix/update_checker"
require "dependabot/nix/versioned_name"
require "dependabot/nix/ignore_filter"
require "dependabot/git_metadata_fetcher"
require "dependabot/git_ref"

module Dependabot
  module Nix
    class UpdateChecker
      # Detects versioned branch naming patterns (e.g. nixos-24.11, release-24.11)
      # and finds the latest branch matching the same prefix.
      class VersionedBranchFinder
        extend T::Sig

        sig do
          params(
            current_ref: String,
            dependency: Dependabot::Dependency,
            credentials: T::Array[Dependabot::Credential],
            ignored_versions: T::Array[String]
          ).void
        end
        def initialize(current_ref:, dependency:, credentials:, ignored_versions: [])
          @current_ref = current_ref
          @dependency = dependency
          @credentials = credentials
          @ignored_versions = ignored_versions
        end

        # Returns true if the current ref looks like a versioned branch.
        sig { returns(T::Boolean) }
        def versioned_branch?
          current_name.versioned?
        end

        # Returns the latest versioned branch info or nil if no newer branch exists.
        # Returns { branch: "nixos-25.05", commit_sha: "abc123" } or nil.
        sig { returns(T.nilable(T::Hash[Symbol, String])) }
        def latest_versioned_branch
          return unless current_name.versioned?

          find_latest_branch
        end

        private

        sig { returns(String) }
        attr_reader :current_ref

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(T::Array[String]) }
        attr_reader :ignored_versions

        sig { returns(VersionedName) }
        def current_name
          @current_name ||= T.let(VersionedName.new(current_ref), T.nilable(VersionedName))
        end

        sig { returns(T.nilable(T::Hash[Symbol, String])) }
        def find_latest_branch
          candidates = remote_branches.filter_map { |ref| build_candidate(ref) }

          latest = candidates.max_by { |c| c[:version] }
          return unless latest

          { branch: latest[:branch].to_s, commit_sha: latest[:commit_sha].to_s }
        end

        sig { params(ref: Dependabot::GitRef).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
        def build_candidate(ref)
          candidate = VersionedName.new(ref.name)
          return unless candidate.same_family?(current_name)
          return unless candidate.newer_than?(current_name)
          return if ignore_filter.ignored?(candidate.version_string)

          { branch: ref.name, commit_sha: ref.commit_sha, version: candidate.version }
        end

        sig { returns(IgnoreFilter) }
        def ignore_filter
          @ignore_filter ||= T.let(IgnoreFilter.new(ignored_versions), T.nilable(IgnoreFilter))
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
              url: T.must(dependency.source_string("url")),
              credentials: credentials
            ),
            T.nilable(Dependabot::GitMetadataFetcher)
          )
        end
      end
    end
  end
end
