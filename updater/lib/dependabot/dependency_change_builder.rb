# frozen_string_literal: true

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
    def self.create_from(**kwargs)
      new(**kwargs).run
    end

    def initialize(job:, dependency_files:, updated_dependencies:, change_source:)
      @job = job
      @dependency_files = dependency_files
      @updated_dependencies = updated_dependencies
      @change_source = change_source
    end

    def run
      updated_files = generate_dependency_files
      # Remove any unchanged dependencies from the updated list
      updated_deps = updated_dependencies.reject do |d|
        # Avoid rejecting the source dependency
        next false if source_dependency_name && d.name == source_dependency_name
        next true if d.top_level? && d.requirements == d.previous_requirements

        d.version == d.previous_version
      end

      Dependabot::DependencyChange.new(
        job: job,
        updated_dependencies: updated_deps,
        updated_dependency_files: updated_files,
        dependency_group: source_dependency_group
      )
    end

    private

    attr_reader :job, :dependency_files, :updated_dependencies, :change_source

    def source_dependency_name
      return nil unless change_source.is_a? Dependabot::Dependency

      change_source.name
    end

    def source_dependency_group
      return nil unless change_source.is_a? Dependabot::DependencyGroup

      change_source
    end

    def generate_dependency_files
      if updated_dependencies.count == 1
        updated_dependency = updated_dependencies.first
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
      file_updater_for(relevant_dependencies).updated_dependency_files
    end

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
