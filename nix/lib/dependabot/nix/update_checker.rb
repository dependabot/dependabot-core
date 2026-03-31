# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/nix/version"
require "dependabot/nix/requirement"
require "dependabot/nix/nixpkgs_version"
require "dependabot/git_commit_checker"

module Dependabot
  module Nix
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      extend T::Sig

      require_relative "update_checker/latest_version_finder"
      require_relative "update_checker/nixpkgs_branch_finder"

      sig { override.returns(T.nilable(T.any(String, Dependabot::Version))) }
      def latest_version
        @latest_version ||=
          T.let(
            fetch_latest_version,
            T.nilable(T.any(String, Dependabot::Version))
          )
      end

      sig { override.returns(T.nilable(T.any(String, Dependabot::Version))) }
      def latest_resolvable_version
        # Resolvability isn't an issue for flake inputs — they're independent.
        latest_version
      end

      sig { override.returns(T.nilable(T.any(String, Dependabot::Version))) }
      def latest_resolvable_version_with_no_unlock
        # No concept of "unlocking" for flake inputs
        latest_version
      end

      sig { override.returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def updated_requirements
        return dependency.requirements unless nixpkgs_input?

        new_branch = latest_nixpkgs_branch
        return dependency.requirements unless new_branch

        dependency.requirements.map do |req|
          source = req.fetch(:source, {})
          req.merge(
            requirement: new_branch,
            source: source.merge(branch: new_branch, ref: new_branch)
          )
        end
      end

      private

      sig { override.returns(T::Boolean) }
      def latest_version_resolvable_with_full_unlock?
        # Full unlock checks aren't relevant for flake inputs
        false
      end

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def updated_dependencies_after_full_unlock
        raise NotImplementedError
      end

      sig { returns(T::Boolean) }
      def nixpkgs_input?
        source = dependency.requirements.first&.dig(:source)
        source&.dig(:nixpkgs) == true
      end

      sig { returns(T.nilable(String)) }
      def latest_nixpkgs_branch
        @latest_nixpkgs_branch ||= T.let(
          NixpkgsBranchFinder.new(
            dependency: dependency,
            credentials: credentials
          ).latest_branch,
          T.nilable(String)
        )
      end

      sig { returns(T.nilable(String)) }
      def fetch_latest_version
        if nixpkgs_input?
          # For nixpkgs inputs, the "version" is the branch name
          latest_nixpkgs_branch || dependency.version
        else
          LatestVersionFinder.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            ignored_versions: ignored_versions,
            security_advisories: security_advisories,
            cooldown_options: update_cooldown,
            raise_on_ignored: raise_on_ignored
          ).latest_tag
        end
      end
    end
  end
end

Dependabot::UpdateCheckers.register("nix", Dependabot::Nix::UpdateChecker)
