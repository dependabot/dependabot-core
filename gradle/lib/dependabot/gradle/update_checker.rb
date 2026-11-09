# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/gradle/file_parser"

module Dependabot
  module Gradle
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      extend T::Sig

      require_relative "update_checker/requirements_updater"
      require_relative "update_checker/version_finder"
      require_relative "update_checker/multi_dependency_updater"

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
          options: T::Hash[Symbol, T.anything]
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
        super(
          dependency: with_vulnerable_resolution(dependency, security_advisories),
          dependency_files: dependency_files,
          credentials: credentials,
          repo_contents_path: repo_contents_path,
          ignored_versions: ignored_versions,
          raise_on_ignored: raise_on_ignored,
          security_advisories: security_advisories,
          requirements_update_strategy: requirements_update_strategy,
          dependency_group: dependency_group,
          update_cooldown: update_cooldown,
          options: options
        )
      end

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def latest_version
        return if git_dependency?

        version_from_details(latest_version_details)
      end

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def latest_resolvable_version
        # TODO: Resolve the build.gradle to find the latest version we could
        # update to without updating any other dependencies at the same time.
        #
        # The above is hard. Currently we just return the latest version and
        # hope (hence this package manager is in beta!)
        return if git_dependency?
        return nil if version_comes_from_multi_dependency_property?
        return nil if version_comes_from_dependency_set?

        latest_version
      end

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def lowest_security_fix_version
        version_from_details(lowest_security_fix_version_details)
      end

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def lowest_resolvable_security_fix_version
        return if git_dependency?
        return nil if version_comes_from_multi_dependency_property?
        return nil if version_comes_from_dependency_set?

        lowest_security_fix_version
      end

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def latest_resolvable_version_with_no_unlock
        # Irrelevant, since Gradle has a single dependency file.
        #
        # For completeness we ought to resolve the build.gradle and return the
        # latest version that satisfies the current constraint AND any
        # constraints placed on it by other dependencies. Seeing as we're
        # never going to take any action as a result, though, we just return
        # nil.
        nil
      end

      sig { override.returns(T::Array[Dependabot::DependencyRequirement]) }
      def updated_requirements
        property_names =
          declarations_using_a_property
          .filter_map { |req| property_name_from_requirement(req) }

        RequirementsUpdater.new(
          requirements: dependency.requirements,
          latest_version: preferred_resolvable_version&.to_s,
          source_url: source_url_from_details(preferred_version_details),
          properties_to_update: property_names
        ).updated_requirements
      end

      sig { override.returns(T::Boolean) }
      def requirements_unlocked_or_can_be?
        # If the dependency version come from a property we couldn't
        # interpolate then there's nothing we can do.
        !dependency.version&.include?("$")
      end

      private

      # A lockfile-only dependency can resolve to several versions. The combined
      # dependency (the one carrying `all_versions`) is re-based onto its highest
      # vulnerable resolved version, so the fix covers every vulnerable resolution
      # whichever security-update path built the checker. Individual `all_versions`
      # entries keep their own version, so selecting the vulnerable entry still
      # works. The advisories are recorded so the updater can validate every
      # regenerated version against them.
      sig do
        params(
          dependency: Dependabot::Dependency,
          security_advisories: T::Array[Dependabot::SecurityAdvisory]
        ).returns(Dependabot::Dependency)
      end
      def with_vulnerable_resolution(dependency, security_advisories)
        return dependency if security_advisories.empty? || !dependency.requirements.empty?
        return dependency if dependency.metadata_string_array(:lockfiles).to_a.empty?

        metadata = dependency.metadata.merge(advisories: advisory_metadata(security_advisories))
        version = dependency.version
        vulnerable = vulnerable_resolved_versions(dependency, security_advisories)
        unless vulnerable.empty?
          version = vulnerable.max_by { |candidate| Gradle::Version.new(candidate) }
          metadata = metadata.merge(vulnerable_versions: vulnerable)
        end

        Dependency.new(
          name: dependency.name,
          version: version,
          requirements: [],
          package_manager: dependency.package_manager,
          metadata: metadata
        )
      end

      sig do
        params(
          dependency: Dependabot::Dependency,
          security_advisories: T::Array[Dependabot::SecurityAdvisory]
        ).returns(T::Array[String])
      end
      def vulnerable_resolved_versions(dependency, security_advisories)
        resolved = dependency.metadata_string_array(:resolved_versions)
        return [] unless dependency.metadata[:all_versions] && resolved

        resolved.select do |candidate|
          Gradle::Version.correct?(candidate) &&
            security_advisories.any? { |advisory| advisory.vulnerable?(Gradle::Version.new(candidate)) }
        end
      end

      sig do
        params(security_advisories: T::Array[Dependabot::SecurityAdvisory])
          .returns(T::Array[T::Hash[Symbol, T::Array[String]]])
      end
      def advisory_metadata(security_advisories)
        security_advisories.map do |advisory|
          {
            vulnerable: advisory.vulnerable_version_strings.map(&:to_s),
            safe: advisory.safe_versions.map(&:to_s)
          }
        end
      end

      sig { override.returns(T::Boolean) }
      def latest_version_resolvable_with_full_unlock?
        unless version_comes_from_multi_dependency_property? ||
               version_comes_from_dependency_set?
          return false
        end

        multi_dependency_updater.update_possible?
      end

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def updated_dependencies_after_full_unlock
        multi_dependency_updater.updated_dependencies
      end

      sig { override.returns(T::Boolean) }
      def numeric_version_up_to_date?
        return false unless version_class.correct?(dependency.version)

        super
      end

      sig { override.params(requirements_to_unlock: T.nilable(Symbol)).returns(T::Boolean) }
      def numeric_version_can_update?(requirements_to_unlock:)
        return false unless version_class.correct?(dependency.version)
        # Without requirements or a lockfile to regenerate there is nothing to update
        return false if dependency.requirements.empty? && dependency.metadata_string_array(:lockfiles).to_a.empty?

        super
      end

      sig { returns(T.nilable(T::Hash[Symbol, Object])) }
      def preferred_version_details
        return lowest_security_fix_version_details if vulnerable?

        latest_version_details
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
        @version_finder ||= T.let(
          VersionFinder.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            ignored_versions: ignored_versions,
            raise_on_ignored: raise_on_ignored,
            cooldown_options: update_cooldown,
            security_advisories: security_advisories
          ),
          T.nilable(VersionFinder)
        )
      end

      sig { returns(MultiDependencyUpdater) }
      def multi_dependency_updater
        @multi_dependency_updater ||= T.let(
          MultiDependencyUpdater.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            target_version_details: latest_version_details,
            ignored_versions: ignored_versions,
            raise_on_ignored: raise_on_ignored
          ),
          T.nilable(MultiDependencyUpdater)
        )
      end

      sig { params(details: T.nilable(T::Hash[Symbol, Object])).returns(T.nilable(Dependabot::Version)) }
      def version_from_details(details)
        version = details&.fetch(:version, nil)
        version if version.is_a?(Dependabot::Version)
      end

      sig { params(details: T.nilable(T::Hash[Symbol, Object])).returns(T.nilable(String)) }
      def source_url_from_details(details)
        source_url = details&.fetch(:source_url, nil)
        source_url if source_url.is_a?(String)
      end

      sig { returns(T::Boolean) }
      def git_dependency?
        git_commit_checker.git_dependency?
      end

      sig { returns(Dependabot::GitCommitChecker) }
      def git_commit_checker
        @git_commit_checker ||= T.let(
          GitCommitChecker.new(
            dependency: dependency,
            credentials: credentials
          ),
          T.nilable(Dependabot::GitCommitChecker)
        )
      end

      sig { returns(T::Boolean) }
      def version_comes_from_multi_dependency_property?
        declarations_using_a_property.any? do |requirement|
          property_name = property_name_from_requirement(requirement)
          next false unless property_name

          all_property_based_dependencies.any? do |dep|
            next false if dep.name == dependency.name

            dep.requirements.any? do |req|
              req.metadata_string("property_name") == property_name
            end
          end
        end
      end

      sig { params(requirement: Dependabot::DependencyRequirement).returns(T.nilable(String)) }
      def property_name_from_requirement(requirement)
        requirement.metadata_string("property_name")
      end

      sig { returns(T::Boolean) }
      def version_comes_from_dependency_set?
        dependency.requirements.any? do |req|
          req.metadata_string_hash("dependency_set")
        end
      end

      sig { returns(T::Array[Dependabot::DependencyRequirement]) }
      def declarations_using_a_property
        @declarations_using_a_property ||= T.let(
          dependency.requirements
                    .select { |req| req.metadata_string("property_name") },
          T.nilable(T::Array[Dependabot::DependencyRequirement])
        )
      end

      sig { returns(T::Array[Dependabot::Dependency]) }
      def all_property_based_dependencies
        @all_property_based_dependencies ||= T.let(
          Gradle::FileParser.new(
            dependency_files: dependency_files,
            source: nil
          ).parse.select do |dep|
            dep.requirements.any? { |req| req.metadata_string("property_name") }
          end,
          T.nilable(T::Array[Dependabot::Dependency])
        )
      end
    end
  end
end

Dependabot::UpdateCheckers.register("gradle", Dependabot::Gradle::UpdateChecker)
