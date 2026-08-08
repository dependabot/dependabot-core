# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/update_checkers"
require "dependabot/update_checkers/base"

module Dependabot
  module Powershell
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      extend T::Sig

      require_relative "update_checker/latest_version_finder"
      require_relative "update_checker/requirements_updater"

      sig { override.returns(T.nilable(T.any(String, Gem::Version))) }
      def latest_version
        latest_version_finder.latest_version
      end

      sig { override.returns(T.nilable(T.any(String, Gem::Version))) }
      def latest_resolvable_version
        # The PowerShell Gallery has no dependency-resolution step of its
        # own (module manifests don't pin transitive dependency versions in
        # a way that requires a native resolver), so the latest version is
        # always resolvable.
        latest_version
      end

      sig { override.returns(T.nilable(T.any(String, Gem::Version))) }
      def latest_resolvable_version_with_no_unlock
        latest_version_finder.latest_version_with_no_unlock
      end

      sig { override.returns(T.nilable(Gem::Version)) }
      def lowest_security_fix_version
        latest_version_finder.lowest_security_fix_version
      end

      sig { override.returns(T.nilable(Gem::Version)) }
      def lowest_resolvable_security_fix_version
        lowest_security_fix_version
      end

      sig { override.returns(T::Array[Dependabot::DependencyRequirement]) }
      def updated_requirements
        requirements = RequirementsUpdater.new(
          requirements: dependency.requirements,
          latest_resolvable_version: preferred_resolvable_version&.to_s
        ).updated_requirements

        wrap_requirements(
          requirements_with_updated_guid(requirements)
        )
      end

      private

      sig { override.returns(T::Boolean) }
      def version_up_to_date?
        return latest_version.to_s == T.must(dependency.version) if exact_pin?

        super
      end

      # PowerShell declaration styles have update semantics that differ from
      # generic requirement satisfaction. For example, a ModuleVersion
      # minimum tracks the latest release even when the current floor already
      # permits it, while an unrewritable below-floor range is left unchanged.
      # Use the updater's actual output as the freshness decision so
      # `up_to_date?` and `updated_requirements` stay aligned.
      sig { override.returns(T::Boolean) }
      def requirements_up_to_date?
        updated_requirements.each_with_index.all? do |updated, index|
          original = dependency.requirements[index]
          original && updated.requirement == original.requirement
        end
      end

      sig { override.returns(T::Boolean) }
      def latest_version_resolvable_with_full_unlock?
        # Full unlock (updating other dependencies to help this one update)
        # isn't supported for PowerShell modules.
        false
      end

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def updated_dependencies_after_full_unlock
        raise NotImplementedError
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
            raise_on_ignored: raise_on_ignored
          ),
          T.nilable(LatestVersionFinder)
        )
      end

      sig do
        params(requirements: T::Array[Dependabot::DependencyRequirement])
          .returns(T::Array[Dependabot::DependencyRequirement])
      end
      def requirements_with_updated_guid(requirements)
        return requirements unless requirements.any? { |requirement| guid_qualified_required_version?(requirement) }

        target_guid = target_manifest_guid
        return requirements unless target_guid

        requirements.map do |requirement|
          next requirement unless guid_qualified_required_version?(requirement)

          metadata = T.must(requirement.metadata)
          current_guid = metadata.fetch(:guid, nil)
          next requirement unless current_guid.is_a?(String) && current_guid != target_guid

          Dependabot::DependencyRequirement.create(
            requirement.merge(metadata: metadata.merge(updated_guid: target_guid))
          )
        end
      end

      sig { returns(T.nilable(String)) }
      def target_manifest_guid
        target_version = preferred_resolvable_version
        return unless target_version

        latest_version_finder.manifest_guid_for(target_version.to_s)
      end

      sig { params(requirement: Dependabot::DependencyRequirement).returns(T::Boolean) }
      def guid_qualified_required_version?(requirement)
        metadata = requirement.metadata
        return false unless metadata

        metadata.fetch(:version_key, nil) == "RequiredVersion" && metadata.fetch(:guid, nil).is_a?(String)
      end

      sig { returns(T::Boolean) }
      def exact_pin?
        dependency.requirements.any? do |requirement|
          requirement.metadata&.fetch(:version_key, nil) == "RequiredVersion"
        end
      end
    end
  end
end

Dependabot::UpdateCheckers.register("powershell", Dependabot::Powershell::UpdateChecker)
