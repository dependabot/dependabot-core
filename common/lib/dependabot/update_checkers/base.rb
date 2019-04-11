# frozen_string_literal: true

require "json"
require "dependabot/utils"

module Dependabot
  module UpdateCheckers
    class Base
      attr_reader :dependency, :dependency_files, :credentials,
                  :ignored_versions, :security_advisories,
                  :requirements_update_strategy

      def initialize(dependency:, dependency_files:, credentials:,
                     ignored_versions: [], security_advisories: [],
                     requirements_update_strategy: nil)
        @dependency = dependency
        @dependency_files = dependency_files
        @credentials = credentials
        @requirements_update_strategy = requirements_update_strategy
        @ignored_versions = ignored_versions
        @security_advisories = security_advisories
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
        return false if ignore_reqs.include?(requirement_class.new(">= 0"))

        if dependency.version
          version_can_update?(requirements_to_unlock: requirements_to_unlock)
        else
          # TODO: Handle full unlock updates for dependencies without a lockfile
          return false if requirements_to_unlock == :none

          requirements_can_update?
        end
      end

      def updated_dependencies(requirements_to_unlock:)
        unless can_update?(requirements_to_unlock: requirements_to_unlock)
          return []
        end

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

      def latest_resolvable_version
        raise NotImplementedError
      end

      def latest_resolvable_version_with_no_unlock
        raise NotImplementedError
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

      # For some langauges, the manifest file may be constructed such that
      # Dependabot has no way to update it (e.g., if it fetches its versions
      # from a web API). This method is overridden in those cases.
      def requirements_unlocked_or_can_be?
        true
      end

      def vulnerable?
        return false if security_advisory_reqs.none?

        # Can't (currently) detect whether dependencies without a version
        # (i.e., for repos without a lockfile) are vulnerable
        return false unless dependency.version

        # Can't (currently) detect whether git dependencies are vulnerable
        return false if existing_version_is_sha?

        version = dependency.version
        security_advisory_reqs.any? do |advisory|
          in_safe_range =
            advisory.fetch(:safe_versions, []).
            any? { |r| r.satisfied_by?(version_class.new(version)) }

          # If version is known safe for this advisory, it's not vulnerable
          next false if in_safe_range

          in_vulnerable_range =
            advisory.fetch(:vulnerable_versions, []).
            any? { |r| r.satisfied_by?(version_class.new(version)) }

          # If in the vulnerable range and not known safe, it's vulnerable
          next true if in_vulnerable_range

          # If a vulnerable range present but not met, it's not vulnerable
          next false if advisory.fetch(:vulnerable_versions, []).any?

          # Finally, if no vulnerable range provided, but a safe range provided,
          # and this versions isn't included (checked earler), it's vulnerable
          advisory.fetch(:safe_versions, []).any?
        end
      end

      private

      def latest_version_resolvable_with_full_unlock?
        raise NotImplementedError
      end

      def updated_dependency_without_unlock
        Dependency.new(
          name: dependency.name,
          version: latest_resolvable_version_with_no_unlock.to_s,
          requirements: dependency.requirements,
          previous_version: dependency.version,
          previous_requirements: dependency.requirements,
          package_manager: dependency.package_manager
        )
      end

      def updated_dependency_with_own_req_unlock
        Dependency.new(
          name: dependency.name,
          version: latest_resolvable_version.to_s,
          requirements: updated_requirements,
          previous_version: dependency.version,
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
          new_version = latest_resolvable_version
          new_version && !new_version.to_s.start_with?(dependency.version)
        when :all
          latest_version_resolvable_with_full_unlock?
        else raise "Unknown unlock level '#{requirements_to_unlock}'"
        end
      end

      def numeric_version_up_to_date?
        return false unless latest_version

        # If a lockfile isn't out of date and the package has switched to a git
        # source then we'll get a numeric version switching to a git SHA. In
        # this case we treat the verison as up-to-date so that it's ignored.
        return true if latest_version.to_s.match?(/^[0-9a-f]{40}$/)

        latest_version <= version_class.new(dependency.version)
      end

      def numeric_version_can_update?(requirements_to_unlock:)
        return false if numeric_version_up_to_date?

        case requirements_to_unlock&.to_sym
        when :none
          new_version = latest_resolvable_version_with_no_unlock
          new_version && new_version > version_class.new(dependency.version)
        when :own
          new_version = latest_resolvable_version
          new_version && new_version > version_class.new(dependency.version)
        when :all
          latest_version_resolvable_with_full_unlock?
        else raise "Unknown unlock level '#{requirements_to_unlock}'"
        end
      end

      def requirements_up_to_date?
        return true if (updated_requirements - dependency.requirements).none?
        return false unless latest_version
        return false unless version_class.correct?(latest_version.to_s)
        return false unless version_from_requirements

        version_from_requirements >= version_class.new(latest_version.to_s)
      end

      def version_from_requirements
        @version_from_requirements ||=
          dependency.requirements.map { |r| r.fetch(:requirement) }.compact.
          flat_map { |req_str| requirement_class.requirements_array(req_str) }.
          flat_map(&:requirements).
          reject { |req_array| req_array.first.start_with?("<") }.
          map(&:last).
          max
      end

      def requirements_can_update?
        changed_reqs = updated_requirements - dependency.requirements

        return false if changed_reqs.none?

        changed_reqs.none? { |r| r[:requirement] == :unfixable }
      end

      def ignore_reqs
        ignored_versions.map { |req| requirement_class.new(req.split(",")) }
      end

      def security_advisory_reqs
        @security_advisory_reqs ||= security_advisories.map do |vuln|
          vulnerable_versions =
            vuln.fetch(:vulnerable_versions, []).flat_map do |vuln_str|
              requirement_class.requirements_array(vuln_str)
            end

          safe_versions =
            vuln.fetch(:safe_versions, []).flat_map do |safe_str|
              requirement_class.requirements_array(safe_str)
            end

          {
            vulnerable_versions: vulnerable_versions,
            safe_versions: safe_versions
          }
        end
      end
    end
  end
end
