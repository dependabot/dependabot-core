# typed: strict
# frozen_string_literal: true

require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/julia/registry_client"
require "dependabot/julia/requirement"

module Dependabot
  module Julia
    # Load helper classes
    autoload :LatestVersionFinder, "dependabot/julia/update_checker/latest_version_finder"
    autoload :RequirementsUpdater, "dependabot/julia/update_checker/requirements_updater"

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
        ).void
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
        @custom_registries = T.let(nil, T.nilable(T::Array[T::Hash[Symbol, T.untyped]]))
      end

      sig { override.returns(T.nilable(Gem::Version)) }
      def latest_version
        @latest_version ||= T.let(latest_version_finder.latest_version, T.nilable(Gem::Version))
      end

      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def custom_registries
        return @custom_registries if @custom_registries

        registries_config = T.cast(options[:registries], T.nilable(T::Hash[Symbol, T.anything]))
        registries = T.cast(registries_config&.dig(:julia), T.nilable(T::Array[T.untyped])) || []
        # Convert string keys to symbols if needed
        @custom_registries = registries.map do |registry|
          if registry.is_a?(Hash)
            registry.transform_keys(&:to_sym)
          else
            T.cast(registry, T::Hash[Symbol, T.untyped])
          end
        end
      end

      sig { override.returns(T.nilable(Gem::Version)) }
      def latest_resolvable_version
        # For Julia, the latest version is generally resolvable since
        # the manifest file locks exact versions, so we use latest_version
        @latest_resolvable_version ||= T.let(latest_version, T.nilable(Gem::Version))
      end

      sig { override.returns(T.nilable(T.any(Dependabot::Version, String))) }
      def latest_resolvable_version_with_no_unlock
        # Return the highest available version that satisfies the current
        # requirement constraints. requirements_array applies Julia compat
        # semantics (implicit caret, tilde, hyphen ranges) and returns
        # alternatives that are OR'd together.
        candidates = latest_version_finder.available_versions
        return nil if candidates.empty?

        current_requirement = dependency.requirements.first&.requirement

        best = if current_requirement.nil? || current_requirement.strip == "*"
                 candidates.max
               else
                 reqs = requirement_class.requirements_array(current_requirement)
                 candidates.select { |version| reqs.any? { |req| req.satisfied_by?(version) } }.max
               end
        return nil unless best

        Dependabot::Julia::Version.new(best.to_s)
      end

      sig { override.returns(T::Array[Dependabot::DependencyRequirement]) }
      def updated_requirements
        Dependabot::Julia::RequirementsUpdater.new(
          requirements: dependency.requirements,
          target_version: latest_resolvable_version&.to_s,
          update_strategy: requirements_update_strategy&.to_s&.to_sym
        ).updated_requirements
      end

      private

      sig { returns(Dependabot::Julia::LatestVersionFinder) }
      def latest_version_finder
        @latest_version_finder ||= T.let(
          Dependabot::Julia::LatestVersionFinder.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            ignored_versions: ignored_versions,
            security_advisories: security_advisories,
            raise_on_ignored: raise_on_ignored,
            cooldown_config: cooldown_config,
            custom_registries: custom_registries
          ),
          T.nilable(Dependabot::Julia::LatestVersionFinder)
        )
      end

      sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def cooldown_config
        return nil unless update_cooldown

        # Convert the ReleaseCooldownOptions to a hash for compatibility
        cooldown = T.must(update_cooldown) # We know it's not nil due to guard above
        {
          default_days: cooldown.default_days,
          semver_major_days: cooldown.semver_major_days,
          semver_minor_days: cooldown.semver_minor_days,
          semver_patch_days: cooldown.semver_patch_days,
          # ReleaseCooldownOptions stores these as Sets; LatestVersionFinder expects Arrays.
          include: cooldown.include.to_a,
          exclude: cooldown.exclude.to_a
        }
      end

      sig { returns(T.class_of(Dependabot::Julia::Requirement)) }
      def requirement_class
        Dependabot::Julia::Requirement
      end
    end
  end
end

Dependabot::UpdateCheckers.register("julia", Dependabot::Julia::UpdateChecker)
