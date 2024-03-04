# typed: strict
# frozen_string_literal: true

require "json"
require "sorbet-runtime"

require "dependabot/utils"
require "dependabot/security_advisory"

module Dependabot
  module UpdateCheckers
    class Base
      extend T::Sig
      extend T::Helpers

      sig { returns(Dependabot::Dependency) }
      attr_reader :dependency

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      attr_reader :dependency_files

      sig { returns(T.nilable(String)) }
      attr_reader :repo_contents_path

      sig { returns(T::Array[Dependabot::Credential]) }
      attr_reader :credentials

      sig { returns(T::Array[String]) }
      attr_reader :ignored_versions

      sig { returns(T::Boolean) }
      attr_reader :raise_on_ignored

      sig { returns(T::Array[Dependabot::SecurityAdvisory]) }
      attr_reader :security_advisories

      sig { returns(T.nilable(String)) }
      attr_reader :requirements_update_strategy

      sig { returns(T.nilable(Dependabot::DependencyGroup)) }
      attr_reader :dependency_group

      sig { returns(T::Hash[Symbol, T.untyped]) }
      attr_reader :options

      sig do
        params(
          dependency: Dependabot::Dependency,
          dependency_files: T::Array[Dependabot::DependencyFile],
          credentials: T::Array[Dependabot::Credential],
          repo_contents_path: T.nilable(String),
          ignored_versions: T::Array[String],
          raise_on_ignored: T::Boolean,
          security_advisories: T::Array[Dependabot::SecurityAdvisory],
          requirements_update_strategy: T.nilable(String),
          dependency_group: T.nilable(Dependabot::DependencyGroup),
          options: T::Hash[Symbol, T.untyped]
        )
          .void
      end
      def initialize(dependency:, dependency_files:, credentials:,
                     repo_contents_path: nil, ignored_versions: [],
                     raise_on_ignored: false, security_advisories: [],
                     requirements_update_strategy: nil, dependency_group: nil,
                     options: {})
        @dependency = dependency
        @dependency_files = dependency_files
        @repo_contents_path = repo_contents_path
        @credentials = credentials
        @requirements_update_strategy = requirements_update_strategy
        @ignored_versions = ignored_versions
        @raise_on_ignored = raise_on_ignored
        @security_advisories = security_advisories
        @dependency_group = dependency_group
        @options = options
      end

      sig { returns(T::Boolean) }
      def up_to_date?
        if dependency.version
          version_up_to_date?
        else
          requirements_up_to_date?
        end
      end

      sig { params(requirements_to_unlock: T.nilable(Symbol)).returns(T::Boolean) }
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

      sig { params(requirements_to_unlock: T.nilable(Symbol)).returns(T::Array[Dependabot::Dependency]) }
      def updated_dependencies(requirements_to_unlock:)
        return [] unless can_update?(requirements_to_unlock: requirements_to_unlock)

        case requirements_to_unlock&.to_sym
        when :none then [updated_dependency_without_unlock]
        when :own then [updated_dependency_with_own_req_unlock]
        when :all then updated_dependencies_after_full_unlock
        else raise "Unknown unlock level '#{requirements_to_unlock}'"
        end
      end

      sig { overridable.returns(T.nilable(T.any(String, Gem::Version))) }
      def latest_version
        raise NotImplementedError, "#{self.class} must implement #latest_version"
      end

      sig { overridable.returns(T.nilable(T.any(String, Gem::Version))) }
      def preferred_resolvable_version
        # If this dependency is vulnerable, prefer trying to update to the
        # lowest_resolvable_security_fix_version. Otherwise update all the way
        # to the latest_resolvable_version.
        return lowest_resolvable_security_fix_version if vulnerable?

        latest_resolvable_version
      rescue NotImplementedError
        latest_resolvable_version
      end

      sig { overridable.returns(T.nilable(T.any(String, Gem::Version))) }
      def latest_resolvable_version
        raise NotImplementedError, "#{self.class} must implement #latest_resolvable_version"
      end

      # Lowest available security fix version not checking resolvability
      # @return [Dependabot::<package manager>::Version, #to_s] version class
      sig { overridable.returns(Dependabot::Version) }
      def lowest_security_fix_version
        raise NotImplementedError, "#{self.class} must implement #lowest_security_fix_version"
      end

      sig { overridable.returns(String) }
      def lowest_resolvable_security_fix_version
        raise NotImplementedError, "#{self.class} must implement #lowest_resolvable_security_fix_version"
      end

      sig { overridable.returns(T.nilable(T.any(String, Dependabot::Version))) }
      def latest_resolvable_version_with_no_unlock
        raise NotImplementedError, "#{self.class} must implement #latest_resolvable_version_with_no_unlock"
      end

      # Finds any dependencies in the lockfile that have a subdependency on the
      # given dependency that do not satisfy the target_version.
      # @return [Array<Hash{String => String}]
      #   name [String] the blocking dependencies name
      #   version [String] the version of the blocking dependency
      #   requirement [String] the requirement on the target_dependency
      sig { overridable.returns(T::Array[T::Hash[String, String]]) }
      def conflicting_dependencies
        [] # return an empty array for ecosystems that don't support this yet
      end

      sig { params(_updated_version: String).returns(T.nilable(String)) }
      def latest_resolvable_previous_version(_updated_version)
        dependency.version
      end

      sig { overridable.returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def updated_requirements
        raise NotImplementedError
      end

      sig { returns(T.class_of(Dependabot::Version)) }
      def version_class
        dependency.version_class
      end

      sig { returns(T.class_of(Dependabot::Requirement)) }
      def requirement_class
        dependency.requirement_class
      end

      # For some languages, the manifest file may be constructed such that
      # Dependabot has no way to update it (e.g., if it fetches its versions
      # from a web API). This method is overridden in those cases.
      sig { returns(T::Boolean) }
      def requirements_unlocked_or_can_be?
        true
      end

      sig { returns(T::Boolean) }
      def vulnerable?
        return false if security_advisories.none?

        # Can't (currently) detect whether dependencies without a version
        # (i.e., for repos without a lockfile) are vulnerable
        return false unless dependency.version

        # Can't (currently) detect whether git dependencies are vulnerable
        return false if existing_version_is_sha?

        active_advisories.any?
      end

      sig { returns(T::Array[Dependabot::Requirement]) }
      def ignore_requirements
        ignored_versions.flat_map { |req| requirement_class.requirements_array(req) }
      end

      private

      sig { returns(T::Array[Dependabot::SecurityAdvisory]) }
      def active_advisories
        security_advisories.select { |a| a.vulnerable?(T.must(current_version)) }
      end

      sig { overridable.returns(T::Boolean) }
      def latest_version_resolvable_with_full_unlock?
        raise NotImplementedError, "#{self.class} must implement #latest_version_resolvable_with_full_unlock?"
      end

      sig { returns(Dependabot::Dependency) }
      def updated_dependency_without_unlock
        version = latest_resolvable_version_with_no_unlock.to_s
        previous_version = latest_resolvable_previous_version(version)&.to_s

        Dependency.new(
          name: dependency.name,
          version: version,
          requirements: dependency.requirements,
          previous_version: previous_version,
          previous_requirements: dependency.requirements,
          package_manager: dependency.package_manager,
          metadata: dependency.metadata,
          subdependency_metadata: dependency.subdependency_metadata
        )
      end

      sig { returns(Dependabot::Dependency) }
      def updated_dependency_with_own_req_unlock
        version = preferred_resolvable_version.to_s
        previous_version = latest_resolvable_previous_version(version)&.to_s

        Dependency.new(
          name: dependency.name,
          version: version,
          requirements: updated_requirements,
          previous_version: previous_version,
          previous_requirements: dependency.requirements,
          package_manager: dependency.package_manager,
          metadata: dependency.metadata,
          subdependency_metadata: dependency.subdependency_metadata
        )
      end

      sig { overridable.returns(T::Array[Dependabot::Dependency]) }
      def updated_dependencies_after_full_unlock
        raise NotImplementedError
      end

      sig { returns(T::Boolean) }
      def version_up_to_date?
        return sha1_version_up_to_date? if existing_version_is_sha?

        numeric_version_up_to_date?
      end

      sig { params(requirements_to_unlock: T.nilable(Symbol)).returns(T::Boolean) }
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

      sig { returns(T::Boolean) }
      def existing_version_is_sha?
        return false if version_class.correct?(dependency.version)

        T.must(dependency.version).match?(/^[0-9a-f]{6,}$/)
      end

      sig { returns(T::Boolean) }
      def sha1_version_up_to_date?
        latest_version&.to_s&.start_with?(T.must(dependency.version)) || false
      end

      sig { params(requirements_to_unlock: T.nilable(Symbol)).returns(T::Boolean) }
      def sha1_version_can_update?(requirements_to_unlock:)
        return false if sha1_version_up_to_date?

        # All we can do with SHA-1 hashes is check for presence and equality
        case requirements_to_unlock&.to_sym
        when :none
          new_version = latest_resolvable_version_with_no_unlock
          !new_version&.to_s&.start_with?(T.must(dependency.version))
        when :own
          preferred_version_resolvable_with_unlock?
        when :all
          latest_version_resolvable_with_full_unlock?
        else raise "Unknown unlock level '#{requirements_to_unlock}'"
        end
      end

      sig { returns(T::Boolean) }
      def numeric_version_up_to_date?
        return false unless latest_version

        # If a lockfile isn't out of date and the package has switched to a git
        # source then we'll get a numeric version switching to a git SHA. In
        # this case we treat the version as up-to-date so that it's ignored.
        return true if latest_version.to_s.match?(/^[0-9a-f]{40}$/)

        T.must(latest_version) <= current_version
      end

      sig { params(requirements_to_unlock: T.nilable(Symbol)).returns(T::Boolean) }
      def numeric_version_can_update?(requirements_to_unlock:)
        return false if numeric_version_up_to_date?

        case requirements_to_unlock&.to_sym
        when :none
          new_version = latest_resolvable_version_with_no_unlock
          return false unless new_version

          new_version > current_version
        when :own
          preferred_version_resolvable_with_unlock?
        when :all
          latest_version_resolvable_with_full_unlock?
        else raise "Unknown unlock level '#{requirements_to_unlock}'"
        end
      end

      sig { returns(T::Boolean) }
      def preferred_version_resolvable_with_unlock?
        new_version = preferred_resolvable_version
        return false unless new_version

        if existing_version_is_sha?
          return false if new_version.to_s.start_with?(T.must(dependency.version))
        elsif new_version <= current_version
          return false
        end

        updated_requirements.none? { |r| r[:requirement] == :unfixable }
      end

      sig { returns(T::Boolean) }
      def requirements_up_to_date?
        if can_compare_requirements?
          return (T.must(version_from_requirements) >= version_class.new(latest_version.to_s))
        end

        changed_requirements.none?
      end

      # TODO: Should this return Dependabot::Version?
      sig { returns(T.nilable(Gem::Version)) }
      def current_version
        @current_version ||=
          T.let(
            dependency.numeric_version,
            T.nilable(Dependabot::Version)
          )
      end

      sig { returns(T::Boolean) }
      def can_compare_requirements?
        (version_from_requirements &&
          latest_version &&
          version_class.correct?(latest_version.to_s)) || false
      end

      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def changed_requirements
        (updated_requirements - dependency.requirements)
      end

      sig { returns(T.nilable(T.any(String, Gem::Version))) }
      def version_from_requirements
        @version_from_requirements ||=
          T.let(
            dependency.requirements.filter_map { |r| r.fetch(:requirement) }
                      .flat_map { |req_str| requirement_class.requirements_array(req_str) }
                      .flat_map(&:requirements)
                      .reject { |req_array| req_array.first.start_with?("<") }
                      .map(&:last)
                      .max,
            T.nilable(T.any(String, Gem::Version))
          )
      end

      sig { returns(T::Boolean) }
      def requirements_can_update?
        return false if changed_requirements.none?

        changed_requirements.none? { |r| r[:requirement] == :unfixable }
      end
    end
  end
end
