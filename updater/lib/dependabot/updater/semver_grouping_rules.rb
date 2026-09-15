# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency"
require "dependabot/dependency_group"
require "dependabot/utils"

module Dependabot
  class Updater
    # Applies a dependency group's "update-types" rules to a single dependency.
    #
    # These rules can only be evaluated once an update checker has resolved the latest version, because
    # they compare the semver level of the update that is actually available against the levels the group
    # accepts. Every other group rule is applied earlier, while the group is being assembled.
    #
    # The caller supplies the "requirements to unlock" calculation as a block so it is only performed for
    # the ecosystems that need it, since it is an expensive operation.
    class SemverGroupingRules
      extend T::Sig

      sig { params(job: Dependabot::Job).void }
      def initialize(job:)
        @job = job
      end

      # This method applies "SemVer Grouping" rules: if the latest update is greater than the update-types,
      # then it should not be in the group, but be an individual PR, or in another group that fits it.
      # SemVer Grouping rules have to be applied after we have a checker, because we need to know the latest version.
      # Other rules are applied earlier in the process.
      # rubocop:disable Metrics/AbcSize
      sig do
        params(
          group: Dependabot::DependencyGroup,
          dependency: Dependabot::Dependency,
          checker: Dependabot::UpdateCheckers::Base,
          requirements_to_unlock: T.proc.returns(Symbol)
        )
          .returns(T::Boolean)
      end
      def allow_grouping?(group, dependency, checker, &requirements_to_unlock)
        update_types = group.update_types
        # There are no group rules defined, so this dependency can be included in the group.
        return true unless update_types

        if job.package_manager == "cargo"
          return cargo_allow_grouping?(group, dependency, checker, requirements_to_unlock)
        end

        version_class = Dependabot::Utils.version_class_for_package_manager(job.package_manager)
        unless version_class.correct?(dependency.version.to_s) && version_class.correct?(checker.latest_version)
          return false
        end

        version = version_class.new(dependency.version.to_s)
        latest_version = version_class.new(checker.latest_version)

        # Not every version class implements .major, .minor, .patch so we calculate it here from the segments
        latest = semver_segments(latest_version)
        current = semver_segments(version)
        # Ensure that semver components are of the same type and can be compared with each other.
        return false unless %i(major minor patch).all? { |k| current[k].instance_of?(latest[k].class) }

        return update_types.include?("major") if T.must(latest[:major]) > T.must(current[:major])
        return update_types.include?("minor") if T.must(latest[:minor]) > T.must(current[:minor])
        return update_types.include?("patch") if T.must(latest[:patch]) > T.must(current[:patch])

        # some ecosystems don't do semver exactly, so anything lower gets individual for now
        false
      end
      # rubocop:enable Metrics/AbcSize

      private

      sig { returns(Dependabot::Job) }
      attr_reader :job

      sig do
        params(
          group: Dependabot::DependencyGroup,
          dependency: Dependabot::Dependency,
          checker: Dependabot::UpdateCheckers::Base,
          requirements_to_unlock: T.proc.returns(Symbol)
        ).returns(T::Boolean)
      end
      def cargo_allow_grouping?(group, dependency, checker, requirements_to_unlock)
        case dependency.metadata[:all_versions]
        when Array
          return cargo_locked_line_updates_allowed?(group, dependency, checker, requirements_to_unlock)
        end

        version_class = Dependabot::Utils.version_class_for_package_manager("cargo")
        latest_version = checker.latest_version
        return false unless version_class.correct?(dependency.version.to_s) && version_class.correct?(latest_version)

        cargo_update_type_allowed?(
          group,
          version_class.new(dependency.version.to_s),
          version_class.new(latest_version)
        )
      end

      sig do
        params(
          group: Dependabot::DependencyGroup,
          dependency: Dependabot::Dependency,
          checker: Dependabot::UpdateCheckers::Base,
          requirements_to_unlock: T.proc.returns(Symbol)
        ).returns(T::Boolean)
      end
      def cargo_locked_line_updates_allowed?(group, dependency, checker, requirements_to_unlock)
        requirements = requirements_to_unlock.call
        return false if requirements == :update_not_possible

        updates = checker.updated_dependencies(requirements_to_unlock: requirements)
                         .select { |updated| updated.name.casecmp?(dependency.name) }
        return false if updates.empty?

        version_class = Dependabot::Utils.version_class_for_package_manager("cargo")
        updates.all? do |updated|
          previous_version = updated.previous_version
          version = updated.version
          next false unless previous_version && version
          next false unless version_class.correct?(previous_version) && version_class.correct?(version)

          cargo_update_type_allowed?(
            group,
            version_class.new(previous_version),
            version_class.new(version)
          )
        end
      end

      sig { params(version: Gem::Version).returns(T::Hash[Symbol, Integer]) }
      def semver_segments(version)
        {
          major: version.segments[0] || 0,
          minor: version.segments[1] || 0,
          patch: version.segments[2] || 0
        }
      end

      sig { params(group: Dependabot::DependencyGroup, version: Gem::Version, latest_version: Gem::Version).returns(T::Boolean) }
      def cargo_update_type_allowed?(group, version, latest_version)
        return true unless Dependabot::Cargo::Version.respond_to?(:update_type)

        actual_update_type = Dependabot::Cargo::Version.update_type(version.to_s, latest_version.to_s)
        group_update_types = group.update_types
        return true unless group_update_types

        group_update_types.include?(actual_update_type)
      end
    end
  end
end
