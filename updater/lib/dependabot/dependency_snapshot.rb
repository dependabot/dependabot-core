# frozen_string_literal: true

require "base64"
require "dependabot/file_parsers"

# This class describes the dependencies obtained from a project at a specific commit SHA
# including both the Dependabot::DependencyFile objects at that reference as well as
# means to parse them into a set of Dependabot::Dependency objects.
#
# This class is the input for a Dependabot::Updater process with Dependabot::DependencyChange
# representing the output.
module Dependabot
  class DependencySnapshot
    def self.create_from_job_definition(job:, job_definition:)
      decoded_dependency_files = job_definition.fetch("base64_dependency_files").map do |a|
        file = Dependabot::DependencyFile.new(**a.transform_keys(&:to_sym))
        file.content = Base64.decode64(file.content).force_encoding("utf-8") unless file.binary? && !file.deleted?
        file
      end

      new(
        job: job,
        base_commit_sha: job_definition.fetch("base_commit_sha"),
        dependency_files: decoded_dependency_files
      )
    end

    attr_reader :base_commit_sha, :dependency_files, :dependencies

    # Returns the subset of all project dependencies which are permitted
    # by the project configuration.
    def allowed_dependencies
      @allowed_dependencies ||= dependencies.select { |d| job.allowed_update?(d) }
    end

    # Returns the subset of all project dependencies which are specifically
    # requested to be updated by the job definition.
    def job_dependencies
      return [] unless job.dependencies&.any?
      return @job_dependencies if defined? @job_dependencies

      # Gradle, Maven and Nuget dependency names can be case-insensitive and
      # the dependency name in the security advisory often doesn't match what
      # users have specified in their manifest.
      #
      # It's technically possibly to publish case-sensitive npm packages to a
      # private registry but shouldn't cause problems here as job.dependencies
      # is set either from an existing PR rebase/recreate or a security
      # advisory.
      job_dependency_names = job.dependencies.map(&:downcase)
      @job_dependencies = dependencies.select do |dep|
        job_dependency_names.include?(dep.name.downcase)
      end
    end

    def job_group_name
      job.dependency_group_to_refresh
    end

    # Returns just the group that is specifically requested to be updated by
    # the job definition
    def job_group
      return nil unless job_group_name
      return @job_group if defined?(@job_group)

      @job_group = groups.fetch(job.dependency_group_to_refresh.to_sym, nil)
    end

    # A dependency snapshot will always have the same set of dependencies since it only depends
    # on the Job and dependency groups, which are static for a given commit.
    def groups
      # The DependencyGroupEngine registers dependencies when the Job is created
      # and it will memoize the dependency groups
      Dependabot::DependencyGroupEngine.dependency_groups(allowed_dependencies)
    end

    def ungrouped_dependencies
      # If no groups are defined, all dependencies are ungrouped by default.
      return allowed_dependencies unless groups.any?

      Dependabot::DependencyGroupEngine.ungrouped_dependencies(allowed_dependencies)
    end

    private

    def initialize(job:, base_commit_sha:, dependency_files:)
      @job = job
      @base_commit_sha = base_commit_sha
      @dependency_files = dependency_files

      @dependencies = parse_files!
    end

    attr_reader :job

    def parse_files!
      dependency_file_parser.parse
    end

    def dependency_file_parser
      Dependabot::FileParsers.for_package_manager(job.package_manager).new(
        dependency_files: dependency_files,
        repo_contents_path: job.repo_contents_path,
        source: job.source,
        credentials: job.credentials,
        reject_external_code: job.reject_external_code?,
        options: job.experiments
      )
    end
  end
end
