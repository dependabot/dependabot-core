# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/gradle/file_parser"
require "dependabot/gradle/file_updater"

module Dependabot
  module Gradle
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      extend T::Sig

      require_relative "update_checker/requirements_updater"
      require_relative "update_checker/version_finder"
      require_relative "update_checker/multi_dependency_updater"

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def latest_version
        return if git_dependency?

        version_from_details(latest_version_details)
      end

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def latest_resolvable_version
        return lowest_resolvable_security_fix_version if transitive_dependency?

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
        return transitive_security_fix_versions.first if transitive_dependency?

        return if git_dependency?
        return nil if version_comes_from_multi_dependency_property?
        return nil if version_comes_from_dependency_set?

        lowest_security_fix_version
      end

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def latest_resolvable_version_with_no_unlock
        return lowest_resolvable_security_fix_version if transitive_dependency?

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
        return false if transitive_dependency?

        # If the dependency version come from a property we couldn't
        # interpolate then there's nothing we can do.
        !dependency.version&.include?("$")
      end

      private

      sig { returns(T::Boolean) }
      def transitive_dependency?
        !dependency.top_level? && Dependabot::Experiments.enabled?(:gradle_transitive_security_updates)
      end

      sig { returns(T::Array[String]) }
      def locked_versions
        versions = (dependency.subdependency_metadata || []).filter_map do |metadata|
          version = metadata[:version]
          version if version.is_a?(String)
        end
        (versions + [dependency.version]).compact.uniq
      end

      sig { returns(T.nilable(Dependabot::Version)) }
      def highest_vulnerable_version
        locked_versions.filter_map do |version|
          next unless security_advisories.any? { |advisory| advisory.affects_version?(version) }

          Gradle::Version.new(version)
        end.max
      end

      sig { returns(Dependabot::Dependency) }
      def dependency_for_version_lookup
        return dependency unless transitive_dependency?

        Dependency.new(
          name: dependency.name,
          version: highest_vulnerable_version&.to_s || dependency.version,
          requirements: [],
          package_manager: dependency.package_manager,
          subdependency_metadata: dependency.subdependency_metadata
        )
      end

      sig { returns(T::Array[Dependabot::Gradle::Version]) }
      def transitive_security_fix_versions
        @transitive_security_fix_versions ||= T.let(
          resolve_transitive_security_fix_versions,
          T.nilable(T::Array[Dependabot::Gradle::Version])
        )
      end

      sig { returns(T::Array[Dependabot::Gradle::Version]) }
      def resolve_transitive_security_fix_versions
        return [] unless vulnerable?

        version = lowest_security_fix_version
        return [] unless version

        FileUpdater::TransitiveDependencyUpdater.new(
          dependency: dependency, dependency_files: dependency_files, repo_contents_path: repo_contents_path
        ).updated_dependency_files(version: version.to_s)
        [version]
      rescue Dependabot::DependencyFileNotResolvable => e
        Dependabot.logger.info("Cannot update transitive Gradle dependency #{dependency.name}: #{e.message}")
        []
      end

      sig { override.returns(Dependabot::Dependency) }
      def updated_dependency_without_unlock
        return super unless transitive_dependency?

        source = { type: "maven_repo", url: source_url_from_details(lowest_security_fix_version_details) }
        Dependency.new(
          name: dependency.name,
          version: lowest_resolvable_security_fix_version&.to_s,
          previous_version: highest_vulnerable_version&.to_s,
          requirements: [],
          previous_requirements: [],
          package_manager: dependency.package_manager,
          metadata: dependency.metadata,
          subdependency_metadata: (dependency.subdependency_metadata || []).map do |metadata|
            metadata.merge(source: source)
          end
        )
      end

      sig { override.returns(Dependabot::Dependency) }
      def updated_dependency_with_own_req_unlock
        return updated_dependency_without_unlock if transitive_dependency?

        super
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
        return false if transitive_dependency? && !vulnerable?
        return false unless version_class.correct?(dependency.version)

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
            dependency: dependency_for_version_lookup,
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
