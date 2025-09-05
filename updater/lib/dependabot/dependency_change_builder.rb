# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/dependency"
require "dependabot/dependency_change"
require "dependabot/file_updaters"
require "dependabot/dependency_group"

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
        notices: T::Array[Dependabot::Notice],
        exclude_paths: T.nilable(T::Array[String])
      ).returns(Dependabot::DependencyChange)
    end
    def self.create_from(job:, dependency_files:, updated_dependencies:, change_source:, notices: [], exclude_paths: [])
      new(
        job: job,
        dependency_files: dependency_files,
        updated_dependencies: updated_dependencies,
        change_source: change_source,
        notices: notices,
        exclude_paths: exclude_paths
      ).run
    end

    sig do
      params(
        job: Dependabot::Job,
        dependency_files: T::Array[Dependabot::DependencyFile],
        updated_dependencies: T::Array[Dependabot::Dependency],
        change_source: T.any(Dependabot::Dependency, Dependabot::DependencyGroup),
        notices: T::Array[Dependabot::Notice],
        exclude_paths: T.nilable(T::Array[String])
      ).void
    end
    def initialize(job:, dependency_files:, updated_dependencies:, change_source:, notices: [], exclude_paths: [])
      @job = job

      dir = Pathname.new(job.source.directory).cleanpath
      @dependency_files = T.let(dependency_files.select { |f| Pathname.new(f.directory).cleanpath == dir },
                                T::Array[Dependabot::DependencyFile])

      raise "Missing directory in dependency files: #{dir}" unless @dependency_files.any?

      @updated_dependencies = updated_dependencies
      @change_source = change_source
      @notices = notices
      @exclude_paths = exclude_paths
    end

    sig { returns(Dependabot::DependencyChange) }
    def run
      updated_files = generate_dependency_files
      raise DependabotError, "FileUpdater failed" unless updated_files.any?

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

    # rubocop:disable Metrics/PerceivedComplexity
    sig { returns(T::Array[Dependabot::DependencyFile]) }
    def generate_dependency_files
      if updated_dependencies.one?
        updated_dependency = T.must(updated_dependencies.first)
        Dependabot.logger.info("Updating #{updated_dependency.name} from " \
                               "#{updated_dependency.previous_version} to " \
                               "#{updated_dependency.version}")
      else
        dependency_names = updated_dependencies.map(&:name)
        Dependabot.logger.info("Updating #{dependency_names.join(', ')}")
      end

      # Ignore dependencies that are tagged as information_only. These will be
      # updated indirectly as a result of a parent dependency update and are
      # only included here to be included in the PR info.
      relevant_dependencies = updated_dependencies.reject(&:informational_only?)
      # Exclude support files since they are not manifests, just needed for supporting the update
      update_files = file_updater_for(relevant_dependencies).updated_dependency_files.reject(&:support_file)
      if Dependabot::Experiments.enabled?(:enable_exclude_paths_subdirectory_manifest_files) && !update_files.empty?
        update_file_names = update_files.map(&:name)
        update_files.reject! do |f|
          Dependabot::FileFiltering.exclude_path?(f.name, @exclude_paths)
        end
        if update_files.empty?
          msg = "No update files found due to exclude-paths. Excluded files: #{update_file_names.join(', ')}"
          Dependabot.logger.info(msg)
          raise msg
        end
      end
      update_files
    end
    # rubocop:enable Metrics/PerceivedComplexity

    sig { params(dependencies: T::Array[Dependabot::Dependency]).returns(Dependabot::FileUpdaters::Base) }
    def file_updater_for(dependencies)
      Dependabot::FileUpdaters.for_package_manager(job.package_manager).new(
        dependencies: dependencies,
        dependency_files: dependency_files,
        repo_contents_path: job.repo_contents_path,
        credentials: job.credentials,
        options: job.experiments
      )
    end
  end
end
