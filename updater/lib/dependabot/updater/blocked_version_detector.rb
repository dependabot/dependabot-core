# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency"
require "dependabot/job/blocked_version"
require "dependabot/utils"

module Dependabot
  class Updater
    # Computes which transitive (indirect) dependencies changed between the
    # original dependency set and the regenerated one, and flags any whose new
    # version matches a configured blocked version requirement.
    #
    # This is pure logic over already-parsed dependencies so it can be exercised
    # without invoking native helpers.
    class BlockedVersionDetector
      extend T::Sig

      # A single transitive dependency change detected after lockfile regeneration.
      class TransitiveChange < T::Struct
        extend T::Sig

        const :name, String
        const :previous_version, T.nilable(String)
        const :new_version, String
        const :blocked_requirement, T.nilable(String)
        const :reason, T.nilable(String)

        sig { returns(T::Boolean) }
        def blocked?
          !blocked_requirement.nil?
        end

        sig { returns(String) }
        def humanized
          from = previous_version || "(new)"
          "#{name} #{from} => #{new_version}"
        end
      end

      sig do
        params(
          package_manager: String,
          blocked_versions: T::Array[Dependabot::Job::BlockedVersion],
          previous_dependencies: T::Array[Dependabot::Dependency],
          current_dependencies: T::Array[Dependabot::Dependency]
        ).void
      end
      def initialize(package_manager:, blocked_versions:, previous_dependencies:, current_dependencies:)
        @package_manager = package_manager
        @blocked_versions = blocked_versions
        @previous_dependencies = previous_dependencies
        @current_dependencies = current_dependencies
      end

      # All transitive dependencies whose version changed (including newly added).
      sig { returns(T::Array[TransitiveChange]) }
      def transitive_changes
        @transitive_changes ||= T.let(compute_transitive_changes, T.nilable(T::Array[TransitiveChange]))
      end

      # The subset of transitive changes that match a configured blocked version.
      sig { returns(T::Array[TransitiveChange]) }
      def blocked_changes
        transitive_changes.select(&:blocked?)
      end

      private

      sig { returns(String) }
      attr_reader :package_manager

      sig { returns(T::Array[Dependabot::Job::BlockedVersion]) }
      attr_reader :blocked_versions

      sig { returns(T::Array[Dependabot::Dependency]) }
      attr_reader :previous_dependencies

      sig { returns(T::Array[Dependabot::Dependency]) }
      attr_reader :current_dependencies

      sig { returns(T::Array[TransitiveChange]) }
      def compute_transitive_changes
        previous_version_sets = version_sets(previous_dependencies)

        current_dependencies.filter_map do |dep|
          name_key = normalise(dep.name)
          current_versions = versions_for(dep)

          # Skip pure direct dependencies (top-level with no transitive versions).
          # But allow processing of deps that carry transitive versions in all_versions,
          # even if top-level, since npm/yarn/pnpm may store the full set there.
          next if dep.top_level? && current_versions.length == 1

          # Diff the full set of resolved versions rather than only `dep.version`.
          # Ecosystems that allow multiple versions of the same dependency
          # (npm/yarn/pnpm) de-dupe by name and expose the *lowest* version via
          # `dep.version`, with the full set in `dep.all_versions`. Comparing the
          # sets ensures a newly-introduced version is detected even when it is
          # not the lowest and even when the lowest version is unchanged.
          previous_versions_set = previous_version_sets[name_key] || []
          added_versions = current_versions - previous_versions_set
          next if added_versions.empty?

          # A change is blocked if *any* newly-introduced version is blocked.
          # Store the blocked match result to avoid redundant checking.
          blocked_match = T.let(nil, T.nilable([String, T.nilable(String)]))
          blocked_version = added_versions.find do |candidate|
            blocked_match = blocked_match_for(dep.name, candidate)
          end

          TransitiveChange.new(
            name: dep.name,
            previous_version: previous_versions_set.any? ? highest_version(previous_versions_set) : nil,
            new_version: blocked_version || highest_version(added_versions),
            blocked_requirement: blocked_match&.first,
            reason: blocked_match&.last
          )
        end
      end

      # Maps each dependency name to the full set of resolved versions, so that
      # multi-version (npm/yarn/pnpm) changes are detected reliably rather than
      # being masked by `Dependency#version` only exposing the lowest version.
      sig { params(dependencies: T::Array[Dependabot::Dependency]).returns(T::Hash[String, T::Array[String]]) }
      def version_sets(dependencies)
        sets = T.let({}, T::Hash[String, T::Array[String]])

        dependencies.each do |dep|
          versions = versions_for(dep)
          next if versions.empty?

          existing = (sets[normalise(dep.name)] ||= [])
          versions.each { |version| existing << version unless existing.include?(version) }
        end

        sets
      end

      sig { params(dependency: Dependabot::Dependency).returns(T::Array[String]) }
      def versions_for(dependency)
        dependency.all_versions.compact
      end

      # The highest parseable version from a set of newly-added versions. Used
      # only to label non-blocked changes for human-readable logging.
      sig { params(versions: T::Array[String]).returns(String) }
      def highest_version(versions)
        parseable = versions.select { |version| version_class.correct?(version) }
        return T.must(versions.last) if parseable.empty?

        T.must(parseable.max_by { |version| version_class.new(version) })
      end

      sig { params(name: String, version: String).returns(T.nilable([String, T.nilable(String)])) }
      def blocked_match_for(name, version)
        return nil unless version_class.correct?(version)

        parsed_version = version_class.new(version)

        Dependabot::Job::BlockedVersion
          .matching(blocked_versions, dependency_name: name, package_manager: package_manager)
          .each do |blocked_version|
            requirement = T.must(blocked_version.version_requirement)
            next unless requirement_satisfied?(requirement, parsed_version)

            return [requirement, blocked_version.reason]
          end

        nil
      end

      sig { params(requirement: String, version: Dependabot::Version).returns(T::Boolean) }
      def requirement_satisfied?(requirement, version)
        requirement_class.requirements_array(requirement).any? do |req|
          req.satisfied_by?(version)
        end
      rescue Gem::Requirement::BadRequirementError
        false
      end

      sig { params(name: String).returns(String) }
      def normalise(name)
        T.must(Dependabot::Dependency.name_normaliser_for_package_manager(package_manager)).call(name)
      end

      sig { returns(T.class_of(Dependabot::Version)) }
      def version_class
        @version_class ||= T.let(
          Dependabot::Utils.version_class_for_package_manager(package_manager),
          T.nilable(T.class_of(Dependabot::Version))
        )
      end

      sig { returns(T.class_of(Dependabot::Requirement)) }
      def requirement_class
        @requirement_class ||= T.let(
          Dependabot::Utils.requirement_class_for_package_manager(package_manager),
          T.nilable(T.class_of(Dependabot::Requirement))
        )
      end
    end
  end
end
