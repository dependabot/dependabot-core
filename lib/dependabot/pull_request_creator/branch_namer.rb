# frozen_string_literal: true

require "dependabot/metadata_finders"
require "dependabot/pull_request_creator"

module Dependabot
  class PullRequestCreator
    class BranchNamer
      attr_reader :dependencies, :files, :target_branch, :separator

      def initialize(dependencies:, files:, target_branch:, separator: "/")
        @dependencies  = dependencies
        @files         = files
        @target_branch = target_branch
        @separator     = separator
      end

      # rubocop:disable Metrics/AbcSize
      # rubocop:disable Metrics/PerceivedComplexity
      # rubocop:disable Metrics/CyclomaticComplexity
      def new_branch_name
        @name ||=
          if dependencies.count > 1 && updating_a_property?
            property_name
          elsif dependencies.count > 1 && updating_a_dependency_set?
            dependency_set.fetch(:group)
          elsif dependencies.count > 1
            dependencies.map(&:name).join("-and-").tr(":", "-")
          elsif library? && ref_changed?(dependencies.first)
            dep = dependencies.first
            "#{dep.name.tr(':', '-')}-#{new_ref(dep)}"
          elsif library?
            dep = dependencies.first
            "#{dep.name.tr(':', '-')}-#{sanitized_requirement(dep)}"
          else
            dep = dependencies.first
            "#{dep.name.tr(':', '-')}-#{new_version(dep)}"
          end

        branch_name = File.join(prefixes, @name).gsub(%r{/\.}, "/dot-")

        # Some users need branch names without slashes
        branch_name.gsub("/", separator)
      end
      # rubocop:enable Metrics/AbcSize
      # rubocop:enable Metrics/PerceivedComplexity
      # rubocop:enable Metrics/CyclomaticComplexity

      private

      def prefixes
        [
          "dependabot",
          package_manager,
          files.first.directory.tr(" ", "-"),
          target_branch
        ].compact
      end

      def package_manager
        dependencies.first.package_manager
      end

      def updating_a_property?
        dependencies.first.
          requirements.
          any? { |r| r.dig(:metadata, :property_name) }
      end

      def updating_a_dependency_set?
        dependencies.first.
          requirements.
          any? { |r| r.dig(:metadata, :dependency_set) }
      end

      def property_name
        @property_name ||= dependencies.first.requirements.
                           find { |r| r.dig(:metadata, :property_name) }&.
                           dig(:metadata, :property_name)

        raise "No property name!" unless @property_name

        @property_name
      end

      def dependency_set
        @dependency_set ||= dependencies.first.requirements.
                            find { |r| r.dig(:metadata, :dependency_set) }&.
                            dig(:metadata, :dependency_set)

        raise "No dependency set!" unless @dependency_set

        @dependency_set
      end

      def sanitized_requirement(dependency)
        new_library_requirement(dependency).
          delete(" ").
          gsub("!=", "neq-").
          gsub(">=", "gte-").
          gsub("<=", "lte-").
          gsub("~>", "tw-").
          gsub("^", "tw-").
          gsub("||", "or-").
          gsub("~", "approx-").
          gsub("~=", "tw-").
          gsub(/==*/, "eq-").
          gsub(">", "gt-").
          gsub("<", "lt-").
          gsub("*", "star").
          gsub(",", "-and-")
      end

      def new_version(dependency)
        if dependency.version.match?(/^[0-9a-f]{40}$/)
          return new_ref(dependency) if ref_changed?(dependency)

          dependency.version[0..6]
        elsif dependency.version == dependency.previous_version &&
              package_manager == "docker"
          dependency.requirements.
            map { |r| r.dig(:source, "digest") || r.dig(:source, :digest) }.
            compact.first.split(":").last[0..6]
        else
          dependency.version
        end
      end

      def previous_ref(dependency)
        dependency.previous_requirements.map do |r|
          r.dig(:source, "ref") || r.dig(:source, :ref)
        end.compact.first
      end

      def new_ref(dependency)
        dependency.requirements.map do |r|
          r.dig(:source, "ref") || r.dig(:source, :ref)
        end.compact.first
      end

      def ref_changed?(dependency)
        previous_ref(dependency) && new_ref(dependency) &&
          previous_ref(dependency) != new_ref(dependency)
      end

      def new_library_requirement(dependency)
        updated_reqs =
          dependency.requirements - dependency.previous_requirements

        gemspec =
          updated_reqs.find { |r| r[:file].match?(%r{^[^/]*\.gemspec$}) }
        return gemspec[:requirement] if gemspec

        updated_reqs.first[:requirement]
      end

      def library?
        if files.map(&:name).any? { |name| name.match?(%r{^[^/]*\.gemspec$}) }
          return true
        end

        dependencies.none?(&:appears_in_lockfile?)
      end

      def requirements_changed?(dependency)
        (dependency.requirements - dependency.previous_requirements).any?
      end
    end
  end
end
