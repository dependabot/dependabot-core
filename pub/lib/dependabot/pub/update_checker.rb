# frozen_string_literal: true

require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/pub/helpers"
require "yaml"
module Dependabot
  module Pub
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      include Dependabot::Pub::Helpers

      def latest_version
        version = Dependabot::Pub::Version.new(current_report["latest"])

        return version if ignore_requirements.none? { |r| r.satisfied_by?(version) }
        return version if version == version_class.new(dependency.version)
        return nil unless @raise_on_ignored

        raise AllVersionsIgnored
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

        parse_updated_dependency(entry, requirements_update_strategy: resolved_requirements_update_strategy).
          requirements
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
          parse_updated_dependency(d, requirements_update_strategy: resolved_requirements_update_strategy)
        end
      end

      def report
        @report ||= dependency_services_report
      end

      def current_report
        report.find { |d| d["name"] == dependency.name }
      end

      def resolved_requirements_update_strategy
        @resolved_requirements_update_strategy ||= resolve_requirements_update_strategy
      end

      def resolve_requirements_update_strategy
        raise "Unexpected requirements_update_strategy #{requirements_update_strategy}" unless
          [nil, "widen_ranges", "bump_versions", "bump_versions_if_necessary"].include? requirements_update_strategy

        if requirements_update_strategy.nil?
          # Check for a version field in the pubspec.yaml. If it is present
          # we assume the package is a library, and the requirement update
          # strategy is widening. Otherwise we assume it is an application, and
          # go for "bump_versions".
          pubspec = dependency_files.find { |d| d.name == "pubspec.yaml" }
          begin
            parsed_pubspec = YAML.safe_load(pubspec.content, aliases: false)
          rescue ScriptError
            return "bump_versions"
          end
          if parsed_pubspec["version"].nil?
            "bump_versions"
          else
            "widen_ranges"
          end
        else
          requirements_update_strategy
        end
      end
    end
  end
end

Dependabot::UpdateCheckers.register("pub", Dependabot::Pub::UpdateChecker)
