# frozen_string_literal: true

# This class describes a change to the project's Dependencies which has been
# determined by a Dependabot operation.
#
# It includes a list of changed Dependabot::Dependency objects, an array of
# Dependabot::DependencyFile objects which contain the changes to be applied
# along with any Dependabot::DependencyGroup that was used to generate the change.
#
# This class provides methods for presenting the change set which can be used
# by adapters to create a Pull Request, apply the changes on disk, etc.
module Dependabot
  class DependencyChange
    attr_reader :job, :updated_dependencies, :updated_dependency_files, :dependency_group

    def initialize(job:, updated_dependencies:, updated_dependency_files:, dependency_group: nil)
      @job = job
      @updated_dependencies = updated_dependencies
      @updated_dependency_files = updated_dependency_files
      @dependency_group = dependency_group
    end

    def pr_message
      return @pr_message if defined?(@pr_message)

      @pr_message = Dependabot::PullRequestCreator::MessageBuilder.new(
        source: job.source,
        dependencies: updated_dependencies,
        files: updated_dependency_files,
        credentials: job.credentials,
        commit_message_options: job.commit_message_options,
        dependency_group: dependency_group
      ).message
    end

    def humanized
      updated_dependencies.map do |dependency|
        "#{dependency.name} ( from #{dependency.humanized_previous_version} to #{dependency.humanized_version} )"
      end.join(", ")
    end

    def updated_dependency_files_hash
      updated_dependency_files.map(&:to_h)
    end

    def grouped_update?
      !!dependency_group
    end

    # This method combines checking the job's `updating_a_pull_request` flag
    # with verification the dependencies involved remain the same.
    #
    # If the dependencies involved have changed, we should close the old PR
    # rather than supersede it as the new changes don't necessarily follow
    # from the previous ones; dependencies could have been removed from the
    # project, or pinned by other changes.
    def should_replace_existing_pr?
      return false unless job.updating_a_pull_request?

      # NOTE: Gradle, Maven and Nuget dependency names can be case-insensitive
      # and the dependency name injected from a security advisory often doesn't
      # match what users have specified in their manifest.
      updated_dependencies.map(&:name).map(&:downcase) != job.dependencies.map(&:downcase)
    end

    def matches_existing_pr?
      !!existing_pull_request
    end

    private

    def existing_pull_request
      if grouped_update?
        # We only want PRs for the same group that have the same versions
        job.existing_group_pull_requests.find do |pr|
          pr["dependency-group-name"] == dependency_group.name &&
            Set.new(pr["dependencies"]) == updated_dependencies_set
        end
      else
        job.existing_pull_requests.find { |pr| Set.new(pr) == updated_dependencies_set }
      end
    end

    def updated_dependencies_set
      Set.new(
        updated_dependencies.map do |dep|
          {
            "dependency-name" => dep.name,
            "dependency-version" => dep.version,
            "dependency-removed" => dep.removed? ? true : nil
          }.compact
        end
      )
    end
  end
end
