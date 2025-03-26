# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "yaml"

require "dependabot/pub/helpers"
require "dependabot/requirements_update_strategy"
require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/update_checkers/version_filters"

module Dependabot
  module Pub
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      extend T::Sig

      include Dependabot::Pub::Helpers

      sig { override.returns(T.nilable(T.any(String, Dependabot::Version))) }
      def latest_version
        version = version_unless_ignored(current_report["latest"], current_version: dependency.version)
        raise AllVersionsIgnored if version.nil? && @raise_on_ignored

        version
      end

      sig { override.returns(T.nilable(T.any(String, Dependabot::Version))) }
      def latest_resolvable_version_with_no_unlock
        # Version we can get if we're not allowed to change pubspec.yaml, but we
        # allow changes in the pubspec.lock file.
        entry = current_report["compatible"].find { |d| d["name"] == dependency.name }
        return nil unless entry

        version_unless_ignored(entry["version"])
      end

      sig { override.returns(T.nilable(T.any(String, Dependabot::Version))) }
      def latest_resolvable_version
        # Latest version we can get if we're allowed to unlock the current
        # package in pubspec.yaml
        entry = current_report["singleBreaking"].find { |d| d["name"] == dependency.name }
        return nil unless entry

        version_unless_ignored(entry["version"])
      end

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def lowest_resolvable_security_fix_version
        raise "Dependency not vulnerable!" unless vulnerable?

        lowest_security_fix_version
      end

      sig { override.returns(T.nilable(Dependabot::Version)) }
      def lowest_security_fix_version
        # Don't attempt to do security updates for git dependencies.
        return nil if git_revision? T.must(dependency.version)
        # If the current version is not vulnerable, we stay on it.
        return T.cast(version_unless_ignored(T.must(dependency.version)), Dependabot::Version) unless vulnerable?

        e = dependency_services_smallest_update
        return nil if e.nil?

        upgrade = e.find { |u| u["name"] == dependency.name }

        version = T.must(upgrade)["version"]
        T.cast(version_unless_ignored(version), Dependabot::Version)
      end

      # rubocop:disable Metrics/PerceivedComplexity
      sig { override.returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def updated_requirements
        # Requirements that need to be changed, if obtain:
        # latest_resolvable_version or lowest_security_fix_version
        entry = if vulnerable?
                  updates = dependency_services_smallest_update

                  # Ideally we would like to do any upgrade that migrates away from the vulnerability
                  # but this method can only return a single requirement udate.
                  breaking_changes = updates&.filter { |d| d["previousConstraint"] != d["constraintBumpedIfNeeded"] }

                  # This security update would require unlocking other packages, which is not currently supported.
                  # Because of that, return original requirements, so that no requirements are actually updated and
                  # the error bubbles up as security_update_not_possible to the user.
                  return dependency.requirements if breaking_changes&.size&. > 1

                  updates&.find { |u| u["name"] == dependency.name }
                else
                  current_report["singleBreaking"].find { |d| d["name"] == dependency.name }
                end
        return [] unless entry

        parse_updated_dependency(entry, resolved_requirements_update_strategy)
          .requirements
      end
      # rubocop:enable Metrics/PerceivedComplexity

      private

      # rubocop:disable Metrics/AbcSize
      sig { returns(T.nilable(T::Array[T::Hash[String, T.untyped]])) }
      def dependency_services_smallest_update
        return @smallest_update if @smallest_update

        security_advisories.each do |a|
          # Sanity check, that we only get the advisories for a single package
          # at a time. If we got all advisories for all current dependencies,
          # the helper would be able to handle it, but we would need a better
          # way to find the repository url.
          if a.dependency_name != dependency.name
            raise "Only expected advisories for #{dependency.name} got for #{a.dependency_name}"
          end
        end
        vulnerable_versions = available_versions(dependency).select do |v|
          security_advisories.any? { |a| a.vulnerable?(v) }
        end
        input = {
          # For "smallest update" we don't cache the report to be shared between
          # dependencies, but run a specific report for the current dependency.
          target: dependency.name,
          disallowed:
            [
              {
                name: dependency.name,
                url: repository_url(dependency),
                versions: vulnerable_versions.map { |v| { range: v.to_s } }
              }
            ]
        }
        report = JSON.parse(run_dependency_services("report", stdin_data: JSON.generate(input)))["dependencies"]
        @smallest_update = T.let(
          report.find { |d| d["name"] == dependency.name }["smallestUpdate"],
          T.nilable(T::Array[T::Hash[String, T.untyped]])
        )
      end
      # rubocop:enable Metrics/AbcSize

      # Returns unparsed_version if it looks like a git-revision.
      #
      # Otherwise it will be parsed with Dependabot::Pub::Version.new and
      # checked against the ignored_requirements:
      #
      # * If not ignored the parsed Version object will be returned.
      # * If current_version is non-nil and the parsed version is the same it
      #   will be returned.
      # * Otherwise returns nil
      sig do
        params(
          unparsed_version: String,
          current_version: T.nilable(String)
        )
          .returns(T.nilable(T.any(String, Dependabot::Version)))
      end
      def version_unless_ignored(unparsed_version, current_version: nil)
        if git_revision?(unparsed_version)
          unparsed_version
        else
          new_version = Dependabot::Pub::Version.new(unparsed_version)
          if !current_version.nil? && !git_revision?(current_version) &&
             Dependabot::Pub::Version.new(current_version) == new_version
            return new_version
          end
          return nil if ignore_requirements.any? { |r| r.satisfied_by?(new_version) }

          new_version
        end
      end

      sig { params(version_string: String).returns(T::Boolean) }
      def git_revision?(version_string)
        version_string.match?(/^[0-9a-f]{6,}$/)
      end

      sig { override.returns(T::Boolean) }
      def latest_version_resolvable_with_full_unlock?
        entry = current_report["multiBreaking"].find { |d| d["name"] == dependency.name }
        # This a bit dumb, but full-unlock is only considered if we can get the
        # latest version!
        return false unless entry

        (!git_revision?(entry["version"]) && latest_version == Dependabot::Pub::Version.new(entry["version"])) ||
          latest_version == entry["version"]
      end

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def updated_dependencies_after_full_unlock
        report_section = if vulnerable?
                           dependency_services_smallest_update
                         else
                           current_report["multiBreaking"]
                         end
        # We only expose non-transitive dependencies here...
        direct_deps = report_section.reject do |d|
          d["kind"] == "transitive"
        end
        direct_deps.map do |d|
          parse_updated_dependency(d, resolved_requirements_update_strategy)
        end
      end

      sig { returns(T::Array[T::Hash[String, T.untyped]]) }
      def report
        @report ||= T.let(
          dependency_services_report,
          T.nilable(T::Array[T::Hash[String, T.untyped]])
        )
      end

      sig { returns(T::Hash[String, T.untyped]) }
      def current_report
        T.must(report.find { |d| d["name"] == dependency.name })
      end

      sig { returns(Dependabot::RequirementsUpdateStrategy) }
      def resolved_requirements_update_strategy
        @resolved_requirements_update_strategy ||= T.let(
          resolve_requirements_update_strategy,
          T.nilable(Dependabot::RequirementsUpdateStrategy)
        )
      end

      sig { returns(Dependabot::RequirementsUpdateStrategy) }
      def resolve_requirements_update_strategy
        raise "Unexpected requirements_update_strategy #{requirements_update_strategy}" unless
          [nil, RequirementsUpdateStrategy::WidenRanges, RequirementsUpdateStrategy::BumpVersions,
           RequirementsUpdateStrategy::BumpVersionsIfNecessary].include? requirements_update_strategy

        if requirements_update_strategy.nil?
          # Check for a version field in the pubspec.yaml. If it is present
          # we assume the package is a library, and the requirement update
          # strategy is widening. Otherwise we assume it is an application, and
          # go for RequirementsUpdateStrategy::BumpVersions.
          pubspec = T.must(dependency_files.find { |d| d.name == "pubspec.yaml" })
          begin
            parsed_pubspec = YAML.safe_load(T.must(pubspec.content), aliases: true)
          rescue ScriptError
            return RequirementsUpdateStrategy::BumpVersions
          end
          if parsed_pubspec["version"].nil? || parsed_pubspec["publish_to"] == "none"
            RequirementsUpdateStrategy::BumpVersions
          else
            RequirementsUpdateStrategy::WidenRanges
          end
        else
          T.must(requirements_update_strategy)
        end
      end
    end
  end
end

Dependabot::UpdateCheckers.register("pub", Dependabot::Pub::UpdateChecker)
