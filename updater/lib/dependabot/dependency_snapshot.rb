# typed: strict
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
    extend T::Sig

    sig do
      params(job: Dependabot::Job, job_definition: T::Hash[String, T.untyped]).returns(Dependabot::DependencySnapshot)
    end
    def self.create_from_job_definition(job:, job_definition:)
      decoded_dependency_files = job_definition.fetch("base64_dependency_files").map do |a|
        file = Dependabot::DependencyFile.new(**a.transform_keys(&:to_sym))
        unless file.binary? && !file.deleted?
          file.content = Base64.decode64(T.must(file.content)).force_encoding("utf-8")
        end
        file
      end

      new(
        job: job,
        base_commit_sha: job_definition.fetch("base_commit_sha"),
        dependency_files: decoded_dependency_files
      )
    end

    sig { returns(String) }
    attr_reader :base_commit_sha

    sig { returns(T::Array[Dependabot::DependencyFile]) }
    attr_reader :dependency_files

    sig { returns(T::Array[Dependabot::Dependency]) }
    attr_reader :dependencies

    sig { returns(T::Set[String]) }
    attr_reader :handled_dependencies

    sig { returns(T::Array[Dependabot::Dependency]) }
    attr_reader :allowed_dependencies

    sig { returns(T::Array[Dependabot::Dependency]) }
    attr_reader :job_dependencies

    sig { returns(T.nilable(Dependabot::DependencyGroup)) }
    attr_reader :job_group

    sig { params(dependency_names: T.any(String, T::Array[String])).void }
    def add_handled_dependencies(dependency_names)
      @handled_dependencies += Array(dependency_names)
    end

    sig { returns(T::Array[Dependabot::DependencyGroup]) }
    def groups
      @dependency_group_engine.dependency_groups
    end

    sig { returns(T::Array[Dependabot::Dependency]) }
    def ungrouped_dependencies
      # If no groups are defined, all dependencies are ungrouped by default.
      return allowed_dependencies unless groups.any?

      # Otherwise return dependencies that haven't been handled during the group update portion.
      allowed_dependencies.reject { |dep| @handled_dependencies.include?(dep.name) }
    end

    private

    sig do
      params(job: Dependabot::Job, base_commit_sha: String, dependency_files: T::Array[Dependabot::DependencyFile]).void
    end
    def initialize(job:, base_commit_sha:, dependency_files:)
      @job = job
      @base_commit_sha = base_commit_sha
      @dependency_files = dependency_files
      @handled_dependencies = T.let(Set.new, T::Set[String])

      @dependencies = T.let(parse_files!, T::Array[Dependabot::Dependency])
      @allowed_dependencies = T.let(calculate_allowed_dependencies, T::Array[Dependabot::Dependency])
      @job_dependencies = T.let(calculate_job_dependencies, T::Array[Dependabot::Dependency])

      @dependency_group_engine = T.let(DependencyGroupEngine.from_job_config(job: job),
                                       Dependabot::DependencyGroupEngine)
      @dependency_group_engine.assign_to_groups!(dependencies: allowed_dependencies)
      @job_group = T.let(calculate_job_group, T.nilable(Dependabot::DependencyGroup))
    end

    sig { returns(Dependabot::Job) }
    attr_reader :job

    sig { returns(T::Array[Dependabot::Dependency]) }
    def parse_files!
      dependency_file_parser.parse
    end

    sig { returns(Dependabot::FileParsers::Base) }
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

    # Returns the subset of all project dependencies which are permitted
    # by the project configuration.
    sig { returns(T::Array[Dependabot::Dependency]) }
    def calculate_allowed_dependencies
      if job.security_updates_only?
        dependencies.select { |d| T.must(job.dependencies).include?(d.name) }
      else
        dependencies.select { |d| job.allowed_update?(d) }
      end
    end

    # Returns the subset of all project dependencies which are specifically
    # requested to be updated by the job definition.
    sig { returns(T::Array[Dependabot::Dependency]) }
    def calculate_job_dependencies
      return [] unless job.dependencies&.any?

      # Gradle, Maven and Nuget dependency names can be case-insensitive and
      # the dependency name in the security advisory often doesn't match what
      # users have specified in their manifest.
      #
      # It's technically possibly to publish case-sensitive npm packages to a
      # private registry but shouldn't cause problems here as job.dependencies
      # is set either from an existing PR rebase/recreate or a security
      # advisory.
      job_dependency_names = T.must(job.dependencies).map(&:downcase)
      dependencies.select do |dep|
        job_dependency_names.include?(dep.name.downcase)
      end
    end

    # Returns just the group that is specifically requested to be updated by
    # the job definition
    sig { returns(T.nilable(Dependabot::DependencyGroup)) }
    def calculate_job_group
      return nil unless job.dependency_group_to_refresh

      @dependency_group_engine.find_group(name: T.must(job.dependency_group_to_refresh))
    end
  end
end
