# typed: strict
# frozen_string_literal: true

require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/devbox/version"
require "dependabot/devbox/requirement"

module Dependabot
  module Devbox
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      extend T::Sig

      require_relative "update_checker/latest_version_finder"

      LATEST = T.let("latest", String)

      sig { override.returns(T.nilable(T.any(String, Gem::Version))) }
      def latest_version
        latest_version_finder.latest_version
      end

      sig { override.returns(T.nilable(T.any(String, Gem::Version))) }
      def latest_resolvable_version
        latest_version
      end

      sig { override.returns(T.nilable(String)) }
      def latest_resolvable_version_with_no_unlock
        dependency.version
      end

      sig { override.returns(T::Array[Dependabot::DependencyRequirement]) }
      def updated_requirements
        latest = latest_version
        return dependency.requirements unless latest

        updated = dependency.requirements.map do |req|
          req.merge(requirement: updated_constraint(req[:requirement], latest.to_s))
        end
        wrap_requirements(updated)
      end

      private

      sig { override.returns(T::Boolean) }
      def latest_version_resolvable_with_full_unlock?
        false
      end

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def updated_dependencies_after_full_unlock
        []
      end

      sig { returns(LatestVersionFinder) }
      def latest_version_finder
        @latest_version_finder ||= T.let(
          LatestVersionFinder.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            ignored_versions: ignored_versions,
            security_advisories: security_advisories,
            cooldown_options: update_cooldown
          ),
          T.nilable(LatestVersionFinder)
        )
      end

      # Recomputes the `name@constraint` constraint for the target version,
      # preserving the original constraint's precision:
      #   - "latest"  stays "latest" (the lockfile alone advances)
      #   - a pinned-minor constraint ("3.10") keeps its two segments, so a patch
      #     bump leaves it unchanged and only a minor/major bump rewrites it
      #   - a pinned-exact constraint ("3.10.15") tracks every segment, so any
      #     bump rewrites it
      sig { params(old_constraint: T.nilable(String), latest: String).returns(T.nilable(String)) }
      def updated_constraint(old_constraint, latest)
        return old_constraint if old_constraint.nil? || old_constraint == LATEST

        segment_count = old_constraint.split(".").length
        latest.split(".").first(segment_count).join(".")
      end
    end
  end
end

Dependabot::UpdateCheckers.register("devbox", Dependabot::Devbox::UpdateChecker)
