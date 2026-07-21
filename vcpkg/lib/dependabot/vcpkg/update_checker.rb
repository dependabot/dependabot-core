# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/errors"
require "dependabot/update_checkers"
require "dependabot/update_checkers/base"

module Dependabot
  module Vcpkg
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      extend T::Sig

      require_relative "update_checker/latest_version_finder"

      sig { override.returns(T.nilable(T.any(String, Dependabot::Version))) }
      def latest_version
        @latest_version ||= T.let(
          latest_version_finder.latest_version,
          T.nilable(T.any(String, Dependabot::Version))
        )
      end

      # Vcpkg baselines don't have resolvability issues since we're dealing with
      # git tags from the official repository, so these methods delegate to latest_version
      sig { override.returns(T.nilable(T.any(String, Dependabot::Version))) }
      def latest_resolvable_version = latest_version

      sig { override.returns(T.nilable(T.any(String, Dependabot::Version))) }
      def latest_resolvable_version_with_no_unlock = latest_version

      # The release tag for the current baseline commit SHA (else the SHA), so the
      # PR title's "from" shows the tag, not the "master" ref.
      sig { params(_updated_version: String).returns(T.nilable(String)) }
      def latest_resolvable_previous_version(_updated_version)
        current_version = dependency.version
        return current_version unless registry_dependency? && current_version&.match?(/\A[0-9a-f]{40}\z/)

        latest_version_finder.tag_for_commit_sha(current_version) || current_version
      end

      sig { override.returns(T::Array[Dependabot::DependencyRequirement]) }
      def updated_requirements
        return dependency.requirements unless latest_version

        dependency.requirements.map do |requirement|
          source = requirement.source
          requirement_constraint = requirement.requirement

          if source && registry_dependency?
            # For git dependencies (baselines), update the git ref with the commit SHA
            requirement.with_source(source.merge(ref: latest_release_commit_sha))
          elsif source.nil? && requirement_constraint
            # For port dependencies (no source but has requirement), update the version constraint
            requirement.with_requirement(">=#{latest_version}")
          else
            # Keep the original requirement unchanged for other cases
            requirement
          end
        end
      end

      private

      sig { returns(T::Boolean) }
      def registry_dependency?
        source_string(dependency.source_details(allowed_types: ["git"]), "type") == "git"
      end

      sig { returns(T::Boolean) }
      def port_dependency?
        # A port dependency has no git source but has a requirement constraint
        !registry_dependency? && dependency.requirements.any?(&:requirement)
      end

      # `latest_version` is a git tag but the baseline is a commit SHA, so the base check never
      # matches and reports an up-to-date baseline as stale. Match the release commit SHA by prefix.
      sig { returns(T::Boolean) }
      def sha1_version_up_to_date?
        return super unless registry_dependency?

        latest_commit_sha = latest_release_commit_sha
        return super unless latest_commit_sha

        latest_commit_sha.start_with?(T.must(dependency.version))
      end

      sig { returns(T.nilable(String)) }
      def latest_release_commit_sha
        value = T.cast(latest_version_finder.latest_release_info&.details&.[]("commit_sha"), Object)
        value if value.is_a?(String)
      end

      sig do
        params(
          source: T.nilable(Dependabot::DependencyRequirement::Details),
          key: String
        ).returns(T.nilable(String))
      end
      def source_string(source, key)
        return unless source

        value = source[key] || source[key.to_sym]
        value if value.is_a?(String)
      end

      # Vcpkg doesn't support full unlocking since dependencies are tracked via baselines
      sig { override.returns(T::Boolean) }
      def latest_version_resolvable_with_full_unlock? = false

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def updated_dependencies_after_full_unlock
        raise NotImplementedError, "Vcpkg doesn't support full unlock operations"
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
            cooldown_options: update_cooldown,
            raise_on_ignored: raise_on_ignored,
            options: options
          ),
          T.nilable(LatestVersionFinder)
        )
      end
    end
  end
end

Dependabot::UpdateCheckers.register("vcpkg", Dependabot::Vcpkg::UpdateChecker)
