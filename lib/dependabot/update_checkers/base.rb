# frozen_string_literal: true

require "json"

module Dependabot
  module UpdateCheckers
    class Base
      attr_reader :dependency, :dependency_files, :github_access_token

      def initialize(dependency:, dependency_files:, github_access_token:)
        @dependency = dependency
        @dependency_files = dependency_files
        @github_access_token = github_access_token
      end

      def needs_update?
        if dependency.appears_in_lockfile?
          version_needs_update?
        else
          requirements_need_update?
        end
      end

      def updated_dependency
        return unless needs_update?

        Dependency.new(
          name: dependency.name,
          version: latest_resolvable_version.to_s,
          requirements: updated_requirements,
          previous_version: dependency.version,
          previous_requirements: dependency.requirements,
          package_manager: dependency.package_manager
        )
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

      def version_needs_update?
        return sha1_version_needs_update? if existing_version_is_sha1?
        numeric_version_needs_update?
      end

      def existing_version_is_sha1?
        # 40 characters in the set [0123456789abcdef]
        dependency.version.match?(/^[0-9a-f]{40}$/)
      end

      def sha1_version_needs_update?
        # All we can do with SHA-1 hashes is check for presence and equality
        return false if latest_version && latest_version == dependency.version
        return false if latest_resolvable_version.nil?
        latest_resolvable_version != dependency.version
      end

      def numeric_version_needs_update?
        # Check if we're up-to-date with the latest version.
        # Saves doing resolution if so.
        if latest_version &&
           latest_version <= Gem::Version.new(dependency.version)
          return false
        end

        return false if latest_resolvable_version.nil?

        latest_resolvable_version > Gem::Version.new(dependency.version)
      end

      def requirements_need_update?
        (updated_requirements - dependency.requirements).any? &&
          updated_requirements.none? { |r| r[:requirement] == :unfixable }
      end
    end
  end
end
