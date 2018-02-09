# frozen_string_literal: true

require "json"

module Dependabot
  module UpdateCheckers
    class Base
      attr_reader :dependency, :dependency_files, :credentials

      def initialize(dependency:, dependency_files:, credentials:)
        @dependency = dependency
        @dependency_files = dependency_files
        @credentials = credentials
      end

      def up_to_date?
        if dependency.appears_in_lockfile?
          version_up_to_date?
        else
          requirements_up_to_date?
        end
      end

      def can_update?(unlock_level: :own_requirement)
        if dependency.appears_in_lockfile?
          version_can_update?(unlock_level: unlock_level)
        else
          # TODO: Handle full unlock updates for requirement files
          requirements_can_update?
        end
      end

      def updated_dependencies(unlock_level: :own_requirement)
        return [] unless can_update?(unlock_level: unlock_level)

        case unlock_level
        when :no_requirements
          [
            Dependency.new(
              name: dependency.name,
              version: latest_resolvable_version_with_no_unlock.to_s,
              requirements: dependency.requirements,
              previous_version: dependency.version,
              previous_requirements: dependency.requirements,
              package_manager: dependency.package_manager
            )
          ]
        when :own_requirement
          [
            Dependency.new(
              name: dependency.name,
              version: latest_resolvable_version.to_s,
              requirements: updated_requirements,
              previous_version: dependency.version,
              previous_requirements: dependency.requirements,
              package_manager: dependency.package_manager
            )
          ]
        when :all_requirements
          updated_dependencies_after_full_unlock
        else raise "Unknown unlock level #{unlock_level}"
        end
      end

      def latest_version
        raise NotImplementedError
      end

      def latest_resolvable_version
        raise NotImplementedError
      end

      def latest_resolvable_version_with_no_unlock
        raise NotImplementedError
      end

      def updated_requirements
        raise NotImplementedError
      end

      # Update checkers can (optionally) define their own version class, to be
      # used when comparing and serializing versions
      def version_class
        Gem::Version
      end

      private

      def latest_version_resolvable_with_full_unlock?
        raise NotImplementedError
      end

      def updated_dependencies_after_full_unlock
        raise NotImplementedError
      end

      def version_up_to_date?
        return sha1_version_up_to_date? if existing_version_is_sha1?
        numeric_version_up_to_date?
      end

      def version_can_update?(unlock_level:)
        if existing_version_is_sha1?
          return sha1_version_can_update?(unlock_level: unlock_level)
        end

        numeric_version_can_update?(unlock_level: unlock_level)
      end

      def existing_version_is_sha1?
        dependency.version.match?(/^[0-9a-f]{40}$/)
      end

      def sha1_version_up_to_date?
        latest_version && latest_version == dependency.version
      end

      def sha1_version_can_update?(unlock_level:)
        return false if sha1_version_up_to_date?

        case unlock_level
        when :no_requirements
          return false if latest_resolvable_version_with_no_unlock.nil?
          latest_resolvable_version_with_no_unlock != dependency.version
        when :own_requirement
          # All we can do with SHA-1 hashes is check for presence and equality
          return false if latest_resolvable_version.nil?
          latest_resolvable_version != dependency.version
        when :all_requirements
          latest_version_resolvable_with_full_unlock?
        else raise "Unknown unlock level #{unlock_level}"
        end
      end

      def numeric_version_up_to_date?
        return false unless latest_version
        latest_version <= version_class.new(dependency.version)
      end

      def numeric_version_can_update?(unlock_level:)
        return false if numeric_version_up_to_date?

        case unlock_level
        when :no_requirements
          new_version = latest_resolvable_version_with_no_unlock
          return false if new_version.nil?
          new_version > version_class.new(dependency.version)
        when :own_requirement
          return false if latest_resolvable_version.nil?
          latest_resolvable_version > version_class.new(dependency.version)
        when :all_requirements
          latest_version_resolvable_with_full_unlock?
        else raise "Unknown unlock level #{unlock_level}"
        end
      end

      def requirements_up_to_date?
        (updated_requirements - dependency.requirements).none?
      end

      def requirements_can_update?
        changed_reqs = updated_requirements - dependency.requirements

        return false if changed_reqs.none?
        changed_reqs.none? { |r| r[:requirement] == :unfixable }
      end
    end
  end
end
