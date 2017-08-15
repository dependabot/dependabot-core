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
        if dependency.version
          app_needs_update?
        else
          # If the dependency has no version it means we're updating a library.
          library_needs_update?
        end
      end

      def updated_dependency
        return unless needs_update?

        Dependency.new(
          name: dependency.name,
          version: latest_resolvable_version.to_s,
          requirement: updated_requirement,
          previous_version: dependency.version,
          previous_requirement: dependency.requirement,
          package_manager: dependency.package_manager,
          groups: dependency.groups
        )
      end

      def latest_version
        raise NotImplementedError
      end

      def latest_resolvable_version
        raise NotImplementedError
      end

      def updated_requirement
        raise NotImplementedError
      end

      private

      def app_needs_update?
        # Check if we're up-to-date with the latest version.
        # Saves doing resolution if so.
        if latest_version &&
           latest_version <= Gem::Version.new(dependency.version)
          return false
        end

        return false if latest_resolvable_version.nil?

        latest_resolvable_version > Gem::Version.new(dependency.version)
      end

      def library_needs_update?
        original_requirement =
          Gem::Requirement.new(*dependency.requirement.split(","))

        return false if latest_version.nil?
        return false if original_requirement.satisfied_by?(latest_version)

        !updated_requirement.nil?
      end
    end
  end
end
