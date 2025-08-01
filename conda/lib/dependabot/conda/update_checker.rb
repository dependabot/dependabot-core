# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/conda/version"
require "dependabot/conda/requirement"
require "dependabot/conda/python_package_classifier"

module Dependabot
  module Conda
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      extend T::Sig

      sig do
        params(
          dependency: Dependabot::Dependency,
          dependency_files: T::Array[Dependabot::DependencyFile],
          credentials: T::Array[Dependabot::Credential],
          repo_contents_path: T.nilable(String),
          ignored_versions: T::Array[String],
          raise_on_ignored: T::Boolean,
          security_advisories: T::Array[Dependabot::SecurityAdvisory],
          requirements_update_strategy: T.nilable(Dependabot::RequirementsUpdateStrategy),
          dependency_group: T.nilable(Dependabot::DependencyGroup),
          update_cooldown: T.nilable(Dependabot::Package::ReleaseCooldownOptions),
          options: T::Hash[Symbol, T.untyped]
        )
          .void
      end
      def initialize(dependency:, dependency_files:, credentials:,
                     repo_contents_path: nil, ignored_versions: [],
                     raise_on_ignored: false, security_advisories: [],
                     requirements_update_strategy: nil, dependency_group: nil,
                     update_cooldown: nil, options: {})
        super
        @latest_version = T.let(nil, T.nilable(T.any(String, Dependabot::Version)))
      end

      sig { override.returns(T.nilable(T.any(String, Dependabot::Version))) }
      def latest_version
        @latest_version ||= fetch_latest_version
      end

      sig { override.returns(T.nilable(T.any(String, Dependabot::Version))) }
      def latest_resolvable_version_with_no_unlock
        # For now, same as latest_version since we're not doing full dependency resolution
        latest_version
      end

      sig { override.returns(T.nilable(T.any(String, Dependabot::Version))) }
      def latest_resolvable_version
        # For Phase 3, delegate to latest_version_finder
        # This will be enhanced with actual conda search and PyPI integration
        latest_version
      end

      sig { override.returns(T::Boolean) }
      def up_to_date?
        return true if latest_version.nil?

        # If dependency has no version (range constraint like >=2.0),
        # we can't determine if it's up-to-date, so assume it needs checking
        return false if dependency.version.nil?

        latest_version <= Dependabot::Conda::Version.new(dependency.version)
      end

      sig { override.returns(T::Boolean) }
      def requirements_unlocked_or_can_be?
        # For conda, we don't have lock files, so requirements can always be updated
        # This is unlike other ecosystems that have lock files (package-lock.json, Pipfile.lock, etc.)
        true
      end

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def lowest_security_fix_version
        latest_version_finder.lowest_security_fix_version
      end

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def lowest_resolvable_security_fix_version
        raise "Dependency not vulnerable!" unless vulnerable?

        return @lowest_resolvable_security_fix_version if defined?(@lowest_resolvable_security_fix_version)

        @lowest_resolvable_security_fix_version =
          fetch_lowest_resolvable_security_fix_version
      end

      sig { override.returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def updated_requirements
        target_version = preferred_resolvable_version
        return dependency.requirements unless target_version

        dependency.requirements.map do |req|
          req.merge(
            requirement: update_requirement_string(
              req[:requirement] || "=#{dependency.version}",
              target_version.to_s
            )
          )
        end
      end

      private

      sig { returns(T.nilable(T.any(String, Dependabot::Version))) }
      def fetch_latest_version
        latest_version_finder.latest_version
      end

      sig { returns(LatestVersionFinder) }
      def latest_version_finder
        @latest_version_finder ||= T.let(
          LatestVersionFinder.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            ignored_versions: ignored_versions,
            raise_on_ignored: @raise_on_ignored,
            cooldown_options: @update_cooldown,
            security_advisories: security_advisories
          ),
          T.nilable(LatestVersionFinder)
        )
      end

      sig { returns(T.nilable(Dependabot::Version)) }
      def fetch_lowest_resolvable_security_fix_version
        # Delegate to latest_version_finder for security fix resolution
        # This leverages Python ecosystem's security advisory infrastructure
        latest_version_finder.lowest_security_fix_version
      end

      sig { override.returns(T::Boolean) }
      def latest_version_resolvable_with_full_unlock?
        # For Phase 3, return false as placeholder since we're not doing full dependency resolution
        false
      end

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def updated_dependencies_after_full_unlock
        # For Phase 3, return empty array as placeholder
        []
      end

      sig { params(requirement_string: String, new_version: String).returns(String) }
      def update_requirement_string(requirement_string, new_version)
        # Parse the current requirement to preserve the operator type
        case requirement_string
        when /^=([0-9])/
          # Conda exact version: =1.26 -> =2.3.2
          "=#{new_version}"
        when /^==([0-9])/
          # Pip exact version: ==1.26 -> ==2.3.2
          "==#{new_version}"
        when /^>=([0-9])/
          # Range constraint: preserve as range but update to new version
          ">=#{new_version}"
        when /^>([0-9])/
          # Greater than: >1.26 -> >2.3.2
          ">#{new_version}"
        when /^<=([0-9])/
          # Less than or equal: keep as is (shouldn't be updated)
          requirement_string
        when /^<([0-9])/
          # Less than: keep as is (shouldn't be updated)
          requirement_string
        when /^!=([0-9])/
          # Not equal: keep as is
          requirement_string
        when /^~=([0-9])/
          # Compatible release: ~=1.26 -> ~=2.3.2
          "~=#{new_version}"
        else
          # Default to conda-style equality for unknown patterns
          "=#{new_version}"
        end
      end

      sig { params(package_name: String).returns(T::Boolean) }
      def python_package?(package_name)
        PythonPackageClassifier.python_package?(package_name)
      end
    end
  end
end

require_relative "update_checker/latest_version_finder"

Dependabot::UpdateCheckers.register("conda", Dependabot::Conda::UpdateChecker)
