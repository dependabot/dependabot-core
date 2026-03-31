# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/nix/update_checker"
require "dependabot/nix/nixpkgs_version"
require "dependabot/git_metadata_fetcher"
require "dependabot/git_ref"

module Dependabot
  module Nix
    class UpdateChecker
      # Discovers available nixpkgs branches and finds the latest compatible one.
      #
      # Uses GitMetadataFetcher to enumerate all refs from the nixpkgs repository,
      # filters to valid NixpkgsVersion branch names, and returns the latest branch
      # that is compatible (same prefix + suffix) with the current branch.
      class NixpkgsBranchFinder
        extend T::Sig

        sig do
          params(
            dependency: Dependabot::Dependency,
            credentials: T::Array[T.untyped]
          ).void
        end
        def initialize(dependency:, credentials:)
          @dependency = dependency
          @credentials = credentials
        end

        # Returns the latest compatible branch name, or nil if none found.
        sig { returns(T.nilable(String)) }
        def latest_branch
          current = current_nixpkgs_version
          return nil unless current

          candidates = compatible_branches(current)
          return nil if candidates.empty?

          # The latest compatible branch — but only if it's newer
          best = T.must(candidates.max)
          best > current ? best.branch : nil
        end

        private

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[T.untyped]) }
        attr_reader :credentials

        sig { returns(T.nilable(NixpkgsVersion)) }
        def current_nixpkgs_version
          ref = current_branch
          return nil unless ref
          return nil unless NixpkgsVersion.valid?(ref)

          NixpkgsVersion.new(ref)
        end

        sig { returns(T.nilable(String)) }
        def current_branch
          source = dependency.requirements.first&.dig(:source)
          return nil unless source

          source[:branch] || source[:ref]
        end

        sig { params(current: NixpkgsVersion).returns(T::Array[NixpkgsVersion]) }
        def compatible_branches(current)
          all_refs.filter_map do |ref|
            next unless ref.ref_type == RefType::Head
            next unless NixpkgsVersion.valid?(ref.name)

            version = NixpkgsVersion.new(ref.name)
            next unless version.compatible_with?(current)
            # Only suggest stable releases — don't suggest unstable as an "upgrade"
            next unless version.stable?

            version
          end
        end

        sig { returns(T::Array[Dependabot::GitRef]) }
        def all_refs
          git_metadata_fetcher.refs_for_upload_pack
        end

        sig { returns(Dependabot::GitMetadataFetcher) }
        def git_metadata_fetcher
          @git_metadata_fetcher ||= T.let(
            Dependabot::GitMetadataFetcher.new(
              url: source_url,
              credentials: credentials
            ),
            T.nilable(Dependabot::GitMetadataFetcher)
          )
        end

        sig { returns(String) }
        def source_url
          dependency.requirements.first&.dig(:source, :url) || ""
        end
      end
    end
  end
end
