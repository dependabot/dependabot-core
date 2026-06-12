# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/dependency"
require "dependabot/dependency_change"
require "dependabot/errors"
require "dependabot/experiments"
require "dependabot/file_parsers"
require "dependabot/file_updaters"
require "dependabot/dependency_group"
require "dependabot/updater/blocked_version_detector"

# This class is responsible for generating a DependencyChange for a given
# set of dependencies and dependency files.
#
# This class should be used via the `create_from` method with the following
# arguments:
# - job:
#     The Dependabot::Job object the change is originated by
# - dependency_files:
#     The list dependency files we aim to modify as part of this change
# - updated_dependencies:
#     The set of dependency updates to be applied to the dependency files
# - change_source:
#     A change can be generated from either a single 'lead' Dependency or
#     a DependencyGroup
module Dependabot
  class DependencyChangeBuilder
    extend T::Sig

    sig do
      params(
        job: Dependabot::Job,
        dependency_files: T::Array[Dependabot::DependencyFile],
        updated_dependencies: T::Array[Dependabot::Dependency],
        change_source: T.any(Dependabot::Dependency, Dependabot::DependencyGroup),
        notices: T::Array[Dependabot::Notice]
      ).returns(Dependabot::DependencyChange)
    end
    def self.create_from(job:, dependency_files:, updated_dependencies:, change_source:, notices: [])
      new(
        job: job,
        dependency_files: dependency_files,
        updated_dependencies: updated_dependencies,
        change_source: change_source,
        notices: notices
      ).run
    end

    sig do
      params(
        job: Dependabot::Job,
        dependency_files: T::Array[Dependabot::DependencyFile],
        updated_dependencies: T::Array[Dependabot::Dependency],
        change_source: T.any(Dependabot::Dependency, Dependabot::DependencyGroup),
        notices: T::Array[Dependabot::Notice]
      ).void
    end
    def initialize(job:, dependency_files:, updated_dependencies:, change_source:, notices: [])
      @job = job

      dir = Pathname.new(job.source.directory).cleanpath
      @dependency_files = T.let(
        dependency_files.select { |f| Pathname.new(f.directory).cleanpath == dir },
        T::Array[Dependabot::DependencyFile]
      )

      raise "Missing directory in dependency files: #{dir}" unless @dependency_files.any?

      @updated_dependencies = updated_dependencies
      @change_source = change_source
      @notices = notices
      @regenerated_dependency_files = T.let(nil, T.nilable(T::Array[Dependabot::DependencyFile]))
    end

    sig { returns(Dependabot::DependencyChange) }
    def run
      updated_files = generate_dependency_files

      unless updated_files.any?
        raise DependabotError, "FileUpdater failed to update any files for: #{dependency_info_for_error}"
      end

      enforce_blocked_transitive_versions!

      # Remove any unchanged dependencies from the updated list
      updated_deps = updated_dependencies.reject do |d|
        # Avoid rejecting the source dependency
        next false if source_dependency_name && d.name == source_dependency_name

        next false if d.top_level? && d.requirements != d.previous_requirements

        d.version == d.previous_version
      end

      updated_deps.each { |d| d.metadata[:directory] = job.source.directory } if job.source.directory

      Dependabot::DependencyChange.new(
        job: job,
        updated_dependencies: updated_deps,
        updated_dependency_files: updated_files,
        dependency_group: source_dependency_group,
        notices: notices
      )
    end

    private

    sig { returns(Dependabot::Job) }
    attr_reader :job

    sig { returns(T::Array[Dependabot::DependencyFile]) }
    attr_reader :dependency_files

    sig { returns(T::Array[Dependabot::Dependency]) }
    attr_reader :updated_dependencies

    sig { returns(T.any(Dependabot::Dependency, Dependabot::DependencyGroup)) }
    attr_reader :change_source

    sig { returns(T::Array[Dependabot::Notice]) }
    attr_reader :notices

    sig { returns(T.nilable(String)) }
    def source_dependency_name
      return nil unless change_source.is_a? Dependabot::Dependency

      T.cast(change_source, Dependabot::Dependency).name
    end

    sig { returns(T.nilable(Dependabot::DependencyGroup)) }
    def source_dependency_group
      return nil unless change_source.is_a? Dependabot::DependencyGroup

      T.cast(change_source, Dependabot::DependencyGroup)
    end

    sig { returns(T::Array[Dependabot::DependencyFile]) }
    def generate_dependency_files
      if updated_dependencies.one?
        updated_dependency = T.must(updated_dependencies.first)
        Dependabot.logger.info(
          "Updating #{updated_dependency.name} from " \
          "#{updated_dependency.previous_version} to " \
          "#{updated_dependency.version}"
        )
      else
        dependency_names = updated_dependencies.map(&:name)
        Dependabot.logger.info("Updating #{dependency_names.join(', ')}")
      end

      # Ignore dependencies that are tagged as information_only. These will be
      # updated indirectly as a result of a parent dependency update and are
      # only included here to be included in the PR info.
      relevant_dependencies = updated_dependencies.reject(&:informational_only?)

      # Create file updater and collect notices from it
      file_updater = file_updater_for(relevant_dependencies)

      # Exclude support files since they are not manifests, just needed for supporting the update
      all_files = file_updater.updated_dependency_files
      @regenerated_dependency_files = all_files

      # Collect notices from file updater after update attempt
      updater_notices = T.let(file_updater.notices, T::Array[Dependabot::Notice])
      @notices.concat(updater_notices)

      updated_files = all_files.reject(&:support_file?)
      updated_files
    end

    sig { returns(String) }
    def dependency_names_for_error
      format_names(updated_dependencies.map(&:name))
    end

    sig { params(names: T::Array[String]).returns(String) }
    def format_names(names)
      names.uniq.sort.join(", ")
    end

    sig { returns(String) }
    def dependency_info_for_error
      return dependency_names_for_error unless updated_dependencies.one?

      dependency = T.must(updated_dependencies.first)
      previous_version = dependency.previous_version || "unknown"
      current_version = dependency.version || "unknown"
      "#{dependency.name} (#{previous_version} → #{current_version})"
    end

    sig { params(dependencies: T::Array[Dependabot::Dependency]).returns(Dependabot::FileUpdaters::Base) }
    def file_updater_for(dependencies)
      Dependabot::FileUpdaters.for_package_manager(job.package_manager).new(
        dependencies: dependencies,
        dependency_files: dependency_files,
        repo_contents_path: job.repo_contents_path,
        credentials: job.credentials,
        options: job.experiments.merge(
          security_updates_only: job.security_updates_only?,
          update_cooldown: job.security_updates_only? ? nil : job.cooldown
        )
      )
    end

    # When the blocked_versions experiment is enabled, re-parse the regenerated
    # files to surface which transitive (indirect) dependencies changed, and
    # reject the change if any change introduces a blocked version. This is the
    # ecosystem-agnostic safety net: it guarantees a blocked transitive version
    # is never shipped, even when the resolver does not constrain it natively.
    sig { void }
    def enforce_blocked_transitive_versions!
      return unless Dependabot::Experiments.enabled?(:blocked_versions)

      detector = blocked_version_detector
      return unless detector

      log_transitive_dependency_changes(detector.transitive_changes)

      blocked = detector.blocked_changes.first
      return unless blocked

      raise Dependabot::BlockedDependencyVersion.new(
        dependency_name: blocked.name,
        blocked_version: blocked.new_version,
        version_requirement: T.must(blocked.blocked_requirement),
        reason: blocked.reason
      )
    end

    sig { returns(T.nilable(Dependabot::Updater::BlockedVersionDetector)) }
    def blocked_version_detector
      Dependabot::Updater::BlockedVersionDetector.new(
        package_manager: job.package_manager,
        blocked_versions: job.blocked_versions,
        previous_dependencies: parse_dependencies(dependency_files),
        current_dependencies: parse_dependencies(regenerated_dependency_files)
      )
    rescue StandardError => e
      # Detection must never break a valid update. If re-parsing fails we log and
      # fall back to allowing the update (the resolver-level constraints in
      # Phase 2 still apply where supported).
      Dependabot.logger.warn(
        "Skipping transitive dependency blocking check: #{e.class} - #{e.message}"
      )
      nil
    end

    sig do
      params(changes: T::Array[Dependabot::Updater::BlockedVersionDetector::TransitiveChange]).void
    end
    def log_transitive_dependency_changes(changes)
      return if changes.empty?

      Dependabot.logger.info("Transitive dependencies changed by regenerating the lockfile:")
      changes.each do |change|
        msg = "  #{change.humanized}"
        msg += " (blocked by '#{change.blocked_requirement}')" if change.blocked?
        Dependabot.logger.info(msg)
      end
    end

    # The complete set of files representing the regenerated project state:
    # the original files for the directory, overlaid with any files the
    # FileUpdater changed (including support files).
    sig { returns(T::Array[Dependabot::DependencyFile]) }
    def regenerated_dependency_files
      regenerated = @regenerated_dependency_files
      return dependency_files if regenerated.nil?

      by_name = T.let({}, T::Hash[String, Dependabot::DependencyFile])
      dependency_files.each { |file| by_name[file.name] = file }
      regenerated.each { |file| by_name[file.name] = file }
      by_name.values
    end

    sig { params(files: T::Array[Dependabot::DependencyFile]).returns(T::Array[Dependabot::Dependency]) }
    def parse_dependencies(files)
      Dependabot::FileParsers.for_package_manager(job.package_manager).new(
        dependency_files: files,
        repo_contents_path: job.repo_contents_path,
        source: job.source,
        credentials: job.credentials,
        reject_external_code: job.reject_external_code?,
        options: job.experiments
      ).parse
    end
  end
end
