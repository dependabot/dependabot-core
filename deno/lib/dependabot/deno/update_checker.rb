# typed: strict
# frozen_string_literal: true

require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/deno/version"
require "dependabot/deno/requirement"

module Dependabot
  module Deno
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      extend T::Sig

      require_relative "update_checker/latest_version_finder"

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

      sig { override.returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def updated_requirements
        return dependency.requirements unless latest_version

        dependency.requirements.map do |req|
          req.merge(requirement: updated_constraint(req[:requirement]))
        end
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
            ignored_versions: ignored_versions,
            security_advisories: security_advisories
          ),
          T.nilable(LatestVersionFinder)
        )
      end

      sig { params(old_constraint: T.nilable(String)).returns(String) }
      def updated_constraint(old_constraint)
        return latest_version.to_s unless old_constraint

        latest = latest_version
        return old_constraint unless latest

        if old_constraint.start_with?("^")
          "^#{latest}"
        elsif old_constraint.start_with?("~")
          "~#{latest}"
        elsif old_constraint.match?(/\A[><=]/)
          old_constraint
        else
          latest.to_s
        end
      end
    end
  end
end

Dependabot::UpdateCheckers.register("deno", Dependabot::Deno::UpdateChecker)
