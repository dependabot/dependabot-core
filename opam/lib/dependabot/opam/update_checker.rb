# typed: strong
# frozen_string_literal: true

require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/opam/version"
require "dependabot/opam/requirement"

module Dependabot
  module Opam
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      extend T::Sig

      require_relative "update_checker/version_resolver"

      sig { override.returns(T.nilable(T.any(String, Dependabot::Version))) }
      def latest_version
        @latest_version ||= T.let(
          begin
            version_resolver.latest_version
          end,
          T.nilable(T.any(String, Dependabot::Version))
        )
      end

      sig { override.returns(T.nilable(T.any(String, Dependabot::Version))) }
      def latest_resolvable_version
        # For now, same as latest_version
        # In the future, this could check opam solver constraints
        latest_version
      end

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def lowest_security_fix_version
        # Security advisories not yet supported for opam
        nil
      end

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def lowest_resolvable_security_fix_version
        # Security advisories not yet supported for opam
        nil
      end

      sig { override.returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def updated_requirements
        dependency.requirements.map do |req|
          updated_req = req.dup
          updated_req[:requirement] = updated_version_requirement_string(req)
          updated_req
        end
      end

      private

      sig { returns(VersionResolver) }
      def version_resolver
        @version_resolver ||= T.let(
          VersionResolver.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            ignored_versions: ignored_versions,
            raise_on_ignored: raise_on_ignored,
            security_advisories: security_advisories
          ),
          T.nilable(VersionResolver)
        )
      end

      sig { params(req: T::Hash[Symbol, T.untyped]).returns(String) }
      def updated_version_requirement_string(req)
        current_requirement = req[:requirement]
        return current_requirement if current_requirement.nil? || current_requirement.empty?

        latest = latest_version
        return current_requirement unless latest

        # Parse current requirement
        requirements = current_requirement.split("&").map(&:strip)

        # Update requirements with new version
        updated_reqs = requirements.map do |requirement|
          update_version_in_requirement(requirement, latest.to_s)
        end

        updated_reqs.join(" & ")
      end

      sig { params(requirement: String, new_version: String).returns(String) }
      def update_version_in_requirement(requirement, new_version)
        match = requirement.match(/^([><=!]+)\s*(.+)$/)
        return requirement unless match

        operator = match[1]
        match[2]

        # Keep the same operator, update the version
        case operator
        when "=", "=="
          "= #{new_version}"
        when ">="
          # For >= constraints, update to new minimum
          ">= #{new_version}"
        when ">"
          "> #{new_version}"
        when "<", "<="
          # Don't update upper bounds automatically
          requirement
        when "!="
          # Keep != constraints as-is
          requirement
        else
          requirement
        end
      end

      sig { override.returns(T::Boolean) }
      def latest_version_resolvable_with_full_unlock?
        # For simplicity, assume it's resolvable
        # In the future, this could check opam solver
        true
      end

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def updated_dependencies_after_full_unlock
        # Return just the current dependency
        [dependency]
      end
    end
  end
end

Dependabot::UpdateCheckers
  .register("opam", Dependabot::Opam::UpdateChecker)
