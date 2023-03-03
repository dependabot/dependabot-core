# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/shared_helpers"
require "dependabot/errors"
require "dependabot/go_modules/version"

module Dependabot
  module GoModules
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      extend T::Sig

      require_relative "update_checker/latest_version_finder"

      sig { override.returns(T.nilable(T.any(String, Gem::Version))) }
      def latest_resolvable_version
        latest_version_finder.latest_version
      end

      # This is currently used to short-circuit latest_resolvable_version,
      # with the assumption that it'll be quicker than checking
      # resolvability. As this is quite quick in Go anyway, we just alias.
      sig { override.returns(T.nilable(T.any(String, Gem::Version))) }
      def latest_version
        latest_resolvable_version
      end

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def lowest_resolvable_security_fix_version
        raise "Dependency not vulnerable!" unless vulnerable?

        lowest_security_fix_version
      end

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def lowest_security_fix_version
        latest_version_finder.lowest_security_fix_version
      end

      sig { override.returns(T.nilable(T.any(String, Dependabot::Version))) }
      def latest_resolvable_version_with_no_unlock
        # Irrelevant, since Go modules uses a single dependency file
        nil
      end

      sig { override.returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def updated_requirements
        dependency.requirements.map do |req|
          req.merge(requirement: latest_version)
        end
      end

      private

      sig { returns(Dependabot::GoModules::UpdateChecker::LatestVersionFinder) }
      def latest_version_finder
        @latest_version_finder ||= T.let(
          LatestVersionFinder.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            ignored_versions: ignored_versions,
            security_advisories: security_advisories,
            raise_on_ignored: raise_on_ignored,
            goprivate: options.fetch(:goprivate, "*")
          ),
          T.nilable(Dependabot::GoModules::UpdateChecker::LatestVersionFinder)
        )
      end

      sig { override.returns(T::Boolean) }
      def latest_version_resolvable_with_full_unlock?
        # Full unlock checks aren't implemented for Go (yet)
        false
      end

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def updated_dependencies_after_full_unlock
        raise NotImplementedError
      end

      # Go only supports semver and semver-compliant pseudo-versions, so it can't be a SHA.
      sig { returns(T::Boolean) }
      def existing_version_is_sha?
        false
      end

      sig { params(tag: T.nilable(T::Hash[Symbol, String])).returns(T.untyped) }
      def version_from_tag(tag)
        # To compare with the current version we either use the commit SHA
        # (if that's what the parser picked up) or the tag name.
        return tag&.fetch(:commit_sha) if dependency.version&.match?(/^[0-9a-f]{40}$/)

        tag&.fetch(:tag)
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def default_source
        { type: "default", source: dependency.name }
      end
    end
  end
end

Dependabot::UpdateCheckers
  .register("go_modules", Dependabot::GoModules::UpdateChecker)
