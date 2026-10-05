# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency"
require "dependabot/errors"
require "dependabot/kotlin_toolchain/constants"
require "dependabot/kotlin_toolchain/file_parser/version_catalog_parser"
require "dependabot/kotlin_toolchain/version"
require "dependabot/update_checkers"
require "dependabot/update_checkers/base"

module Dependabot
  module KotlinToolchain
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      extend T::Sig

      require_relative "update_checker/version_finder"

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def latest_version
        version_from_details(latest_version_details)
      end

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def latest_resolvable_version
        return if shared_catalog_version?

        latest_version
      end

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def lowest_security_fix_version
        version_from_details(lowest_security_fix_version_details)
      end

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def lowest_resolvable_security_fix_version
        return if shared_catalog_version?

        lowest_security_fix_version
      end

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def latest_resolvable_version_with_no_unlock
        nil
      end

      sig { override.returns(T::Array[Dependabot::DependencyRequirement]) }
      def updated_requirements
        target = preferred_resolvable_version
        return dependency.requirements unless target.is_a?(Dependabot::Version)

        updated_requirements_for(dependency.requirements, target)
      end

      private

      sig { override.returns(T::Boolean) }
      def latest_version_resolvable_with_full_unlock?
        return false unless shared_catalog_version?

        target = preferred_version
        return false unless target

        catalog_siblings.all? do |sibling|
          version_finder_for(sibling).versions.any? { |details| details.fetch(:version).to_s == target.to_s }
        end
      end

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def updated_dependencies_after_full_unlock
        target = preferred_version
        return [] unless target

        ([dependency] + catalog_siblings).map do |member|
          Dependabot::Dependency.new(
            name: member.name,
            version: target.to_s,
            requirements: updated_requirements_for(member.requirements, target),
            previous_version: member.version,
            previous_requirements: member.requirements,
            package_manager: member.package_manager,
            metadata: member.metadata
          )
        end
      end

      # The same coordinate may be pinned at different versions in different
      # files. Only files below the target are bumped; the rest stay as they
      # are instead of being rewritten downwards.
      sig do
        params(
          requirements: T::Array[Dependabot::DependencyRequirement],
          target: Dependabot::Version
        ).returns(T::Array[Dependabot::DependencyRequirement])
      end
      def updated_requirements_for(requirements, target)
        source_url = source_url_from_details(preferred_version_details)

        updated = requirements.map do |requirement|
          current = requirement[:requirement]
          next requirement if current.is_a?(String) && Version.correct?(current) && Version.new(current) >= target

          source = requirement[:source]
          source = source.merge(url: source_url) if source_url && source.is_a?(Hash)

          {
            file: requirement[:file],
            requirement: target.to_s,
            groups: requirement[:groups],
            source: source,
            metadata: requirement[:metadata]
          }
        end
        wrap_requirements(updated)
      end

      sig { returns(T::Boolean) }
      def shared_catalog_version?
        catalog_siblings.any?
      end

      # Libraries that resolve their version through the same `[versions]` key
      # move together, because the key can only hold one value.
      sig { returns(T::Array[Dependabot::Dependency]) }
      def catalog_siblings
        @catalog_siblings ||= T.let(
          dependency.requirements.flat_map { |requirement| siblings_for(requirement) }.uniq(&:name),
          T.nilable(T::Array[Dependabot::Dependency])
        )
      end

      sig { params(requirement: Dependabot::DependencyRequirement).returns(T::Array[Dependabot::Dependency]) }
      def siblings_for(requirement)
        key = catalog_version_key(requirement)
        file = dependency_files.find { |candidate| candidate.name == requirement[:file] }
        return [] unless key && file

        profile = requirement.metadata_string("profile") || "unknown"
        FileParser::VersionCatalogParser.new(file: file, profile_name: profile).dependencies.select do |candidate|
          candidate.name != dependency.name &&
            candidate.requirements.any? { |sibling| catalog_version_key(sibling) == key }
        end
      end

      sig { params(requirement: Dependabot::DependencyRequirement).returns(T.nilable(String)) }
      def catalog_version_key(requirement)
        return unless requirement.metadata_string("kind") == "catalog_version"

        requirement.metadata_string("version_key")
      end

      sig { returns(T.nilable(Dependabot::Version)) }
      def preferred_version
        vulnerable? ? lowest_security_fix_version : latest_version
      end

      sig { returns(T.nilable(T::Hash[Symbol, Object])) }
      def preferred_version_details
        vulnerable? ? lowest_security_fix_version_details : latest_version_details
      end

      sig { returns(T.nilable(T::Hash[Symbol, Object])) }
      def latest_version_details
        @latest_version_details ||= T.let(
          version_finder.latest_version_details,
          T.nilable(T::Hash[Symbol, Object])
        )
      end

      sig { returns(T.nilable(T::Hash[Symbol, Object])) }
      def lowest_security_fix_version_details
        @lowest_security_fix_version_details ||= T.let(
          version_finder.lowest_security_fix_version_details,
          T.nilable(T::Hash[Symbol, Object])
        )
      end

      sig { returns(VersionFinder) }
      def version_finder
        @version_finder ||= T.let(version_finder_for(dependency), T.nilable(VersionFinder))
      end

      sig { params(target: Dependabot::Dependency).returns(VersionFinder) }
      def version_finder_for(target)
        VersionFinder.new(
          dependency: target,
          dependency_files: dependency_files,
          credentials: credentials,
          ignored_versions: ignored_versions,
          security_advisories: target.equal?(dependency) ? security_advisories : [],
          cooldown_options: update_cooldown,
          raise_on_ignored: raise_on_ignored
        )
      end

      sig do
        params(
          details: T.nilable(T::Hash[Symbol, Object])
        ).returns(T.nilable(Dependabot::Version))
      end
      def version_from_details(details)
        version = details&.fetch(:version, nil)
        return version if version.is_a?(Dependabot::Version)
        return Version.new(version) if version.is_a?(String)

        nil
      end

      sig { params(details: T.nilable(T::Hash[Symbol, Object])).returns(T.nilable(String)) }
      def source_url_from_details(details)
        url = details&.fetch(:source_url, nil)
        url if url.is_a?(String)
      end
    end
  end
end

Dependabot::UpdateCheckers.register(
  "kotlin_toolchain",
  Dependabot::KotlinToolchain::UpdateChecker
)
