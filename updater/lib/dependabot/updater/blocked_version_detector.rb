# typed: strict
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
        previous_versions = version_map(previous_dependencies)

        current_dependencies.filter_map do |dep|
          next if dep.top_level?

          new_version = dep.version
          next if new_version.nil?

          previous_version = previous_versions[normalise(dep.name)]
          next if previous_version == new_version

          blocked = blocked_match_for(dep.name, new_version)

          TransitiveChange.new(
            name: dep.name,
            previous_version: previous_version,
            new_version: new_version,
            blocked_requirement: blocked&.first,
            reason: blocked&.last
          )
        end
      end

      sig { params(dependencies: T::Array[Dependabot::Dependency]).returns(T::Hash[String, String]) }
      def version_map(dependencies)
        dependencies.each_with_object({}) do |dep, map|
          version = dep.version
          next unless version

          map[normalise(dep.name)] = version
        end
      end

      sig { params(name: String, version: String).returns(T.nilable([String, T.nilable(String)])) }
      def blocked_match_for(name, version)
        return nil unless version_class.correct?(version)

        parsed_version = version_class.new(version)
        normalised_name = normalise(name)

        relevant_blocked_versions.each do |blocked_version|
          next unless normalise(T.must(blocked_version.dependency_name)) == normalised_name

          requirement = T.must(blocked_version.version_requirement)
          next unless requirement_satisfied?(requirement, parsed_version)

          return [requirement, blocked_version.reason]
        end

        nil
      end

      sig { returns(T::Array[Dependabot::Job::BlockedVersion]) }
      def relevant_blocked_versions
        @relevant_blocked_versions ||= T.let(
          blocked_versions.select do |blocked_version|
            name = blocked_version.dependency_name
            requirement = blocked_version.version_requirement
            name && !name.strip.empty? && requirement && !requirement.strip.empty?
          end,
          T.nilable(T::Array[Dependabot::Job::BlockedVersion])
        )
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
