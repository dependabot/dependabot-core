# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/conda/version"
require "dependabot/conda/requirement"
require "dependabot/requirements_update_strategy"

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
      def initialize(
        dependency:,
        dependency_files:,
        credentials:,
        repo_contents_path: nil,
        ignored_versions: [],
        raise_on_ignored: false,
        security_advisories: [],
        requirements_update_strategy: nil,
        dependency_group: nil,
        update_cooldown: nil,
        options: {}
      )
        super
        @latest_version = T.let(nil, T.nilable(T.any(String, Dependabot::Version)))
        @lowest_resolvable_security_fix_version = T.let(nil, T.nilable(Dependabot::Version))
        @lowest_resolvable_security_fix_version_fetched = T.let(false, T::Boolean)
      end

      sig { override.returns(T.nilable(T.any(String, Dependabot::Version))) }
      def latest_version
        return nil if dependency.requirements.all? { |req| req[:requirement].nil? || req[:requirement] == "*" }

        @latest_version ||= fetch_latest_version
      end

      sig { override.returns(T.nilable(T.any(String, Dependabot::Version))) }
      def latest_resolvable_version_with_no_unlock
        latest_version
      end

      sig { override.returns(T.nilable(T.any(String, Dependabot::Version))) }
      def latest_resolvable_version
        latest_version
      end

      sig { override.returns(T::Boolean) }
      def up_to_date?
        return true if latest_version.nil?
        return false if dependency.version.nil?

        T.must(latest_version) <= Dependabot::Conda::Version.new(dependency.version)
      end

      sig { override.returns(T::Boolean) }
      def requirements_unlocked_or_can_be?
        true
      end

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def lowest_security_fix_version
        latest_version_finder.lowest_security_fix_version
      end

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def lowest_resolvable_security_fix_version
        raise "Dependency not vulnerable!" unless vulnerable?

        return @lowest_resolvable_security_fix_version if @lowest_resolvable_security_fix_version_fetched

        @lowest_resolvable_security_fix_version = fetch_lowest_resolvable_security_fix_version
        @lowest_resolvable_security_fix_version_fetched = true
        @lowest_resolvable_security_fix_version
      end

      sig { override.returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def updated_requirements
        RequirementsUpdater.new(
          requirements: dependency.requirements,
          update_strategy: requirements_update_strategy,
          latest_resolvable_version: preferred_resolvable_version&.to_s
        ).updated_requirements
      end

      sig { override.returns(Dependabot::RequirementsUpdateStrategy) }
      def requirements_update_strategy
        return @requirements_update_strategy if @requirements_update_strategy

        RequirementsUpdateStrategy::BumpVersions
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
        fix_version = latest_version_finder.lowest_security_fix_version

        if fix_version.nil?
          fallback = latest_resolvable_version
          return fallback.is_a?(String) ? Dependabot::Conda::Version.new(fallback) : fallback
        end

        fix_version
      end

      sig { override.returns(T::Boolean) }
      def latest_version_resolvable_with_full_unlock?
        false
      end

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def updated_dependencies_after_full_unlock
        raise NotImplementedError
      end
    end
  end
end

require_relative "update_checker/latest_version_finder"
require_relative "update_checker/requirements_updater"

Dependabot::UpdateCheckers.register("conda", Dependabot::Conda::UpdateChecker)
