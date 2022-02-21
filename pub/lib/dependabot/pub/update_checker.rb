# frozen_string_literal: true

require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/pub/helpers"

module Dependabot
  module Pub
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      include Dependabot::Pub::Helpers

      def latest_version
        Dependabot::Pub::Version.new(current_report["latest"])
      end

      def latest_resolvable_version_with_no_unlock
        # Version we can get if we're not allowed to change pubspec.yaml, but we
        # allow changes in the pubspec.lock file.
        entry = current_report["compatible"].find { |d| d["name"] == dependency.name }
        return nil unless entry

        new_version = Dependabot::Pub::Version.new(entry["version"])
        # We ignore this solution, if any of the requirements in
        # ignored_versions satisfy the version we're proposing as an upgrade
        # target.
        return nil if ignore_requirements.any? { |r| r.satisfied_by?(new_version) }

        new_version
      end

      def latest_resolvable_version
        # Latest version we can get if we're allowed to unlock the current
        # package in pubspec.yaml
        entry = current_report["singleBreaking"].find { |d| d["name"] == dependency.name }
        return nil unless entry

        new_version = Dependabot::Pub::Version.new(entry["version"])
        # We ignore this solution, if any of the requirements in
        # ignored_versions satisfy the version we're proposing as an upgrade
        # target.
        return nil if ignore_requirements.any? { |r| r.satisfied_by?(new_version) }

        new_version
      end

      def updated_requirements
        # Requirements that need to be changed, if obtain:
        # latest_resolvable_version
        entry = current_report["singleBreaking"].find { |d| d["name"] == dependency.name }
        return unless entry

        to_dependency(entry).requirements
      end

      private

      def latest_version_resolvable_with_full_unlock?
        entry = current_report["multiBreaking"].find { |d| d["name"] == dependency.name }
        # This a bit dumb, but full-unlock is only considered if we can get the
        # latest version!
        entry && latest_version == Dependabot::Pub::Version.new(entry["version"])
      end

      def updated_dependencies_after_full_unlock
        # We only expose non-transitive dependencies here...
        direct_deps = current_report["multiBreaking"].reject do |d|
          d["kind"] == "transitive"
        end
        direct_deps.map do |d|
          to_dependency(d)
        end
      end

      def report
        @report ||= dependency_services_report
      end

      def current_report
        report.find { |d| d["name"] == dependency.name }
      end
    end
  end
end

Dependabot::UpdateCheckers.register("pub", Dependabot::Pub::UpdateChecker)
