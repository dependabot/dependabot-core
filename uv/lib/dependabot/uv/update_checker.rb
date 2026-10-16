# typed: strict
# frozen_string_literal: true

require "excon"
require "toml-rb"
require "sorbet-runtime"

require "dependabot/dependency"
require "dependabot/dependency_requirement"
require "dependabot/errors"
require "dependabot/experiments"
require "dependabot/uv/name_normaliser"
require "dependabot/uv/requirement_parser"
require "dependabot/uv/requirement"
require "dependabot/uv/version"
require "dependabot/registry_client"
require "dependabot/requirements_update_strategy"
require "dependabot/update_checkers"
require "dependabot/python/update_checker"

module Dependabot
  module Uv
    # UV UpdateChecker extends Python's UpdateChecker since both ecosystems
    # share PyPI registry interaction and core version resolution logic.
    # UV overrides only the resolver selection and UV-specific features
    # (uv.lock support, no Pipenv/Poetry support).
    class UpdateChecker < Dependabot::Python::UpdateChecker
      extend T::Sig

      require_relative "update_checker/pip_compile_version_resolver"
      require_relative "update_checker/pip_version_resolver"
      require_relative "update_checker/requirements_updater"
      require_relative "update_checker/latest_version_finder"
      require_relative "update_checker/lock_file_resolver"
      require_relative "update_checker/lockstep_resolver"

      sig { override.returns(T::Array[Dependabot::DependencyRequirement]) }
      def updated_requirements
        RequirementsUpdater.new(
          requirements: dependency.requirements,
          latest_resolvable_version: preferred_resolvable_version&.to_s,
          update_strategy: requirements_update_strategy,
          has_lockfile: requirements_text_file?
        ).updated_requirements
      end

      sig { override.returns(T.nilable(Gem::Version)) }
      def latest_resolvable_version
        lockstep_checked(super)
      end

      sig { override.returns(T.nilable(Gem::Version)) }
      def lowest_resolvable_security_fix_version
        lockstep_checked(super)
      end

      private

      sig { override.returns(T::Boolean) }
      def latest_version_resolvable_with_full_unlock?
        !lockstep_updates.nil?
      end

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def updated_dependencies_after_full_unlock
        T.must(lockstep_updates)
      end

      # Relies on `:own` having been asked first: that probe records `rejected_version`, without which this is nil.
      sig { returns(T.nilable(T::Array[Dependabot::Dependency])) }
      def lockstep_updates
        return unless lockstep_check_applies?

        target = lockstep_resolver.rejected_version
        return unless target

        lockstep_resolver.updated_dependencies_after_full_unlock(target)
      end

      # `:own` claims any registry version is resolvable for pyproject dependencies. When another direct
      # dependency is linked to this one in uv.lock, ask uv, so a lockstep conflict falls through to a full unlock.
      sig { params(candidate: T.nilable(Gem::Version)).returns(T.nilable(Gem::Version)) }
      def lockstep_checked(candidate)
        return candidate if candidate.nil? || !lockstep_check_applies?

        lockstep_resolver.lockstep_conflict?(candidate) ? nil : candidate
      end

      sig { returns(T::Boolean) }
      def lockstep_check_applies?
        Dependabot::Experiments.enabled?(:uv_lockstep_full_unlock) &&
          uv_lock.any? &&
          resolver_type == :requirements &&
          lockstep_resolver.neighbours_in_lockfile?
      end

      sig { returns(LockstepResolver) }
      def lockstep_resolver
        @lockstep_resolver ||= T.let(
          LockstepResolver.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            repo_contents_path: repo_contents_path,
            requirements_update_strategy: requirements_update_strategy,
            update_cooldown: @update_cooldown
          ),
          T.nilable(LockstepResolver)
        )
      end

      sig { override.returns(T.nilable(Gem::Version)) }
      def fetch_lowest_resolvable_security_fix_version
        fix_version = lowest_security_fix_version
        return latest_resolvable_version if fix_version.nil?

        # For requirements and lock_file resolver types, delegate to the resolver
        if resolver_type == :requirements || resolver_type == :lock_file
          resolved_fix = resolver.lowest_resolvable_security_fix_version
          # If no security fix version is found, fall back to latest_resolvable_version
          return resolved_fix || latest_resolvable_version
        end

        resolver.resolvable?(version: fix_version) ? fix_version : nil
      end

      sig { override.returns(T.untyped) }
      def resolver
        case resolver_type
        when :pip_compile then pip_compile_version_resolver
        when :requirements then pip_version_resolver
        when :lock_file then lock_file_resolver
        else raise "Unexpected resolver type #{resolver_type}"
        end
      end

      sig { override.returns(Symbol) }
      def resolver_type
        reqs = requirements

        # If there are no requirements then this is a sub-dependency.
        # It must come from pip-tools or uv.lock.
        return subdependency_resolver if reqs.none?

        # Otherwise, this is a top-level dependency, and we can figure out
        # which resolver to use based on the filename of its requirements
        return :requirements if updating_pyproject?
        return :pip_compile if updating_in_file?
        return :lock_file if updating_uv_lock?

        if dependency.version && !exact_requirement?(reqs)
          subdependency_resolver
        else
          :requirements
        end
      end

      sig { override.returns(Symbol) }
      def subdependency_resolver
        return :pip_compile if pip_compile_files.any?
        return :lock_file if uv_lock.any?

        raise "Claimed to be a sub-dependency, but no lockfile exists!"
      end

      sig { override.params(reqs: T::Array[Dependabot::DependencyRequirement]).returns(T::Boolean) }
      def exact_requirement?(reqs)
        reqs = reqs.filter_map(&:requirement_string)
        reqs = reqs.flat_map { |r| r.split(",").map(&:strip) }
        reqs.any? { |r| Uv::Requirement.new(r).exact? }
      end

      sig { override.returns(Object) }
      def pip_compile_version_resolver
        @pip_compile_version_resolver ||= T.let(
          PipCompileVersionResolver.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            repo_contents_path: repo_contents_path
          ),
          T.nilable(PipCompileVersionResolver)
        )
      end

      sig { override.returns(PipVersionResolver) }
      def pip_version_resolver
        @pip_version_resolver ||= T.let(
          PipVersionResolver.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            ignored_versions: ignored_versions,
            raise_on_ignored: @raise_on_ignored,
            update_cooldown: @update_cooldown,
            security_advisories: security_advisories
          ),
          T.nilable(PipVersionResolver)
        )
      end

      sig { returns(LockFileResolver) }
      def lock_file_resolver
        @lock_file_resolver ||= T.let(
          LockFileResolver.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            repo_contents_path: repo_contents_path,
            security_advisories: security_advisories,
            ignored_versions: ignored_versions,
            update_cooldown: @update_cooldown
          ),
          T.nilable(LockFileResolver)
        )
      end

      sig { override.returns(T.nilable(String)) }
      def current_requirement_string
        reqs = requirements
        return if reqs.none?

        requirement = reqs.find do |r|
          file = r.file
          next false unless file

          file == "uv.lock" || file.end_with?("pyproject.toml") || file.end_with?(".in") || file.end_with?(".txt")
        end

        requirement&.requirement_string
      end

      sig { override.returns(String) }
      def unlocked_requirement_string
        lower_bound_req = updated_version_req_lower_bound

        # Add the latest_version as an upper bound. This means
        # ignore conditions are considered when checking for the latest
        # resolvable version.
        #
        # NOTE: This isn't perfect. If v2.x is ignored and v3 is out but
        # unresolvable then the `latest_version` will be v3, and
        # we won't be ignoring v2.x releases like we should be.
        return lower_bound_req if latest_version.nil?
        return lower_bound_req unless Uv::Version.correct?(latest_version)

        lower_bound_req + ",<=#{latest_version}"
      end

      sig { override.returns(String) }
      def updated_version_req_lower_bound
        return ">=#{dependency.version}" if dependency.version

        version_for_requirement =
          requirements.filter_map(&:requirement_string)
                      .reject { |req_string| req_string.start_with?("<") }
                      .select { |req_string| req_string.match?(VERSION_REGEX) }
                      .map { |req_string| req_string.match(VERSION_REGEX).to_s }
                      .select { |version| Uv::Version.correct?(version) }
                      .max_by { |version| Uv::Version.new(version) }

        ">=#{version_for_requirement || 0}"
      end

      sig { override.returns(LatestVersionFinder) }
      def latest_version_finder
        @latest_version_finder ||= T.let(
          LatestVersionFinder.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            ignored_versions: ignored_versions,
            raise_on_ignored: @raise_on_ignored,
            cooldown_options: @update_cooldown,
            security_advisories: security_advisories
          ),
          T.nilable(LatestVersionFinder)
        )
      end

      sig { returns(T::Boolean) }
      def updating_pyproject?
        requirement_files.any? { |file| file.end_with?("pyproject.toml") }
      end

      sig { returns(T::Boolean) }
      def updating_uv_lock?
        requirement_files.any?("uv.lock")
      end

      sig { returns(T::Boolean) }
      def requirements_text_file?
        requirement_files.any? { |f| f.end_with?("requirements.txt") }
      end

      sig { override.returns(T.nilable(PyprojectDocument::ProjectMetadata)) }
      def library_details
        @library_details ||= T.let(
          pyproject_document.project_metadata || pyproject_document.build_system_metadata,
          T.nilable(PyprojectDocument::ProjectMetadata)
        )
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def uv_lock
        dependency_files.select { |f| f.name == "uv.lock" }
      end
    end
  end
end

Dependabot::UpdateCheckers.register("uv", Dependabot::Uv::UpdateChecker)
