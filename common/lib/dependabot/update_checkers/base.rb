# frozen_string_literal: true

require "json"
require "dependabot/utils"
require "dependabot/security_advisory"

module Dependabot
  module UpdateCheckers
    class Base
      attr_reader :dependency, :dependency_files, :repo_contents_path,
                  :credentials, :ignored_versions, :raise_on_ignored,
                  :security_advisories, :requirements_update_strategy,
                  :options

      def initialize(dependency:, dependency_files:, repo_contents_path: nil,
                     credentials:, ignored_versions: [],
                     raise_on_ignored: false, security_advisories: [],
                     requirements_update_strategy: nil,
                     options: {})
        @dependency = dependency
        @dependency_files = dependency_files
        @repo_contents_path = repo_contents_path
        @credentials = credentials
        @requirements_update_strategy = requirements_update_strategy
        @ignored_versions = ignored_versions
        @raise_on_ignored = raise_on_ignored
        @security_advisories = security_advisories
        @options = options
      end

      def up_to_date?
        if dependency.version
          version_up_to_date?
        else
          requirements_up_to_date?
        end
      end

      def can_update?(requirements_to_unlock:)
        # Can't update if all versions are being ignored
        return false if ignore_requirements.include?(requirement_class.new(">= 0"))

        if dependency.version
          version_can_update?(requirements_to_unlock: requirements_to_unlock)
        else
          # TODO: Handle full unlock updates for dependencies without a lockfile
          return false if requirements_to_unlock == :none

          requirements_can_update?
        end
      end

      def updated_dependencies(requirements_to_unlock:)
        return [] unless can_update?(requirements_to_unlock: requirements_to_unlock)

        case requirements_to_unlock&.to_sym
        when :none then [updated_dependency_without_unlock]
        when :own then [updated_dependency_with_own_req_unlock]
        when :all then updated_dependencies_after_full_unlock
        else raise "Unknown unlock level '#{requirements_to_unlock}'"
        end
      end

      def latest_version
        raise NotImplementedError
      end

      def preferred_resolvable_version
        # If this dependency is vulnerable, prefer trying to update to the
        # lowest_resolvable_security_fix_version. Otherwise update all the way
        # to the latest_resolvable_version.
        return lowest_resolvable_security_fix_version if vulnerable?

        latest_resolvable_version
      rescue NotImplementedError
        latest_resolvable_version
      end

      def latest_resolvable_version
        raise NotImplementedError
      end

      # Lowest available security fix version not checking resolvability
      # @return [Dependabot::<package manager>::Version, #to_s] version class
      def lowest_security_fix_version
        raise NotImplementedError
      end

      def lowest_resolvable_security_fix_version
        raise NotImplementedError
      end

      def latest_resolvable_version_with_no_unlock
        raise NotImplementedError
      end

      # Finds any dependencies in the lockfile that have a subdependency on the
      # given dependency that do not satisfy the target_version.
      # @return [Array<Hash{String => String}]
      #   name [String] the blocking dependencies name
      #   version [String] the version of the blocking dependency
      #   requirement [String] the requirement on the target_dependency
      def conflicting_dependencies
        [] # return an empty array for ecosystems that don't support this yet
      end

      def latest_resolvable_previous_version(_updated_version)
        dependency.version
      end

      def updated_requirements
        raise NotImplementedError
      end

      def version_class
        Utils.version_class_for_package_manager(dependency.package_manager)
      end

      def requirement_class
        Utils.requirement_class_for_package_manager(dependency.package_manager)
      end

      # For some languages, the manifest file may be constructed such that
      # Dependabot has no way to update it (e.g., if it fetches its versions
      # from a web API). This method is overridden in those cases.
      def requirements_unlocked_or_can_be?
        true
      end

      def vulnerable?
        return false if security_advisories.none?

        # Can't (currently) detect whether dependencies without a version
        # (i.e., for repos without a lockfile) are vulnerable
        return false unless dependency.version

        # Can't (currently) detect whether git dependencies are vulnerable
        return false if existing_version_is_sha?

        active_advisories.any?
      end

      def ignore_requirements
        ignored_versions.flat_map { |req| requirement_class.requirements_array(req) }
      end

      private

      def active_advisories
        security_advisories.select { |a| a.vulnerable?(current_version) }
      end

      def latest_version_resolvable_with_full_unlock?
        raise NotImplementedError
      end

      def updated_dependency_without_unlock
        version = latest_resolvable_version_with_no_unlock.to_s
        previous_version = latest_resolvable_previous_version(version)&.to_s

        Dependency.new(
          name: dependency.name,
          version: version,
          requirements: dependency.requirements,
          previous_version: previous_version,
          previous_requirements: dependency.requirements,
          package_manager: dependency.package_manager
        )
      end

      def updated_dependency_with_own_req_unlock
        version = preferred_resolvable_version.to_s
        previous_version = latest_resolvable_previous_version(version)&.to_s

        Dependency.new(
          name: dependency.name,
          version: version,
          requirements: updated_requirements,
          previous_version: previous_version,
          previous_requirements: dependency.requirements,
          package_manager: dependency.package_manager
        )
      end

      def updated_dependencies_after_full_unlock
        raise NotImplementedError
      end

      def version_up_to_date?
        return sha1_version_up_to_date? if existing_version_is_sha?

        numeric_version_up_to_date?
      end

      def version_can_update?(requirements_to_unlock:)
        if existing_version_is_sha?
          return sha1_version_can_update?(
            requirements_to_unlock: requirements_to_unlock
          )
        end

        numeric_version_can_update?(
          requirements_to_unlock: requirements_to_unlock
        )
      end

      def existing_version_is_sha?
        return false if version_class.correct?(dependency.version)

        dependency.version.match?(/^[0-9a-f]{6,}$/)
      end

      def sha1_version_up_to_date?
        latest_version&.to_s&.start_with?(dependency.version)
      end

      def sha1_version_can_update?(requirements_to_unlock:)
        return false if sha1_version_up_to_date?

        # All we can do with SHA-1 hashes is check for presence and equality
        case requirements_to_unlock&.to_sym
        when :none
          new_version = latest_resolvable_version_with_no_unlock
          new_version && !new_version.to_s.start_with?(dependency.version)
        when :own
          preferred_version_resolvable_with_unlock?
        when :all
          latest_version_resolvable_with_full_unlock?
        else raise "Unknown unlock level '#{requirements_to_unlock}'"
        end
      end

      def numeric_version_up_to_date?
        return false unless latest_version

        # If a lockfile isn't out of date and the package has switched to a git
        # source then we'll get a numeric version switching to a git SHA. In
        # this case we treat the version as up-to-date so that it's ignored.
        return true if latest_version.to_s.match?(/^[0-9a-f]{40}$/)

        latest_version <= current_version
      end

      def numeric_version_can_update?(requirements_to_unlock:)
        return false if numeric_version_up_to_date?

        case requirements_to_unlock&.to_sym
        when :none
          new_version = latest_resolvable_version_with_no_unlock
          new_version && new_version > current_version
        when :own
          preferred_version_resolvable_with_unlock?
        when :all
          latest_version_resolvable_with_full_unlock?
        else raise "Unknown unlock level '#{requirements_to_unlock}'"
        end
      end

      def preferred_version_resolvable_with_unlock?
        new_version = preferred_resolvable_version
        return false unless new_version

        if existing_version_is_sha?
          return false if new_version.to_s.start_with?(dependency.version)
        elsif new_version <= current_version
          return false
        end

        updated_requirements.none? { |r| r[:requirement] == :unfixable }
      end

      def requirements_up_to_date?
        if can_compare_requirements?
          return (version_from_requirements >=
                  version_class.new(latest_version.to_s))
        end

        changed_requirements.none?
      end

      def current_version
        @current_version ||= dependency.numeric_version
      end

      def can_compare_requirements?
        version_from_requirements &&
          latest_version &&
          version_class.correct?(latest_version.to_s)
      end

      def changed_requirements
        (updated_requirements - dependency.requirements)
      end

      def version_from_requirements
        @version_from_requirements ||=
          dependency.requirements.filter_map { |r| r.fetch(:requirement) }.
          flat_map { |req_str| requirement_class.requirements_array(req_str) }.
          flat_map(&:requirements).
          reject { |req_array| req_array.first.start_with?("<") }.
          map(&:last).
          max
      end

      def requirements_can_update?
        return false if changed_requirements.none?

        changed_requirements.none? { |r| r[:requirement] == :unfixable }
      end
    end
  end
end
