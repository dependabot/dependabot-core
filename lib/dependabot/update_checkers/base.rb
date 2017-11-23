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

      def can_update?(full_unlock: false)
        if dependency.appears_in_lockfile?
          version_can_update?(full_unlock: full_unlock)
        else
          # TODO: Handle full unlock updates for requirement files
          requirements_can_update?
        end
      end

      def updated_dependencies(full_unlock: false)
        return [] unless can_update?(full_unlock: full_unlock)

        if full_unlock
          updated_dependencies_after_full_unlock
        else
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
        end
      end

      def latest_version
        raise NotImplementedError
      end

      def latest_resolvable_version
        raise NotImplementedError
      end

      def updated_requirements
        raise NotImplementedError
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

      def version_can_update?(full_unlock: false)
        if existing_version_is_sha1?
          return sha1_version_can_update?(full_unlock: full_unlock)
        end

        numeric_version_can_update?(full_unlock: full_unlock)
      end

      def existing_version_is_sha1?
        # 40 characters in the set [0123456789abcdef]
        dependency.version.match?(/^[0-9a-f]{40}$/)
      end

      def sha1_version_up_to_date?
        latest_version && latest_version == dependency.version
      end

      def sha1_version_can_update?(full_unlock: false)
        # All we can do with SHA-1 hashes is check for presence and equality
        return false if sha1_version_up_to_date?

        return latest_version_resolvable_with_full_unlock? if full_unlock
        return false if latest_resolvable_version.nil?
        latest_resolvable_version != dependency.version
      end

      def numeric_version_up_to_date?
        latest_version && latest_version <= Gem::Version.new(dependency.version)
      end

      def numeric_version_can_update?(full_unlock: false)
        # Check if we're up-to-date with the latest version.
        # Saves doing resolution if so.
        return false if numeric_version_up_to_date?

        return latest_version_resolvable_with_full_unlock? if full_unlock
        return false if latest_resolvable_version.nil?
        latest_resolvable_version > Gem::Version.new(dependency.version)
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
