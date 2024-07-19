# typed: strict
# frozen_string_literal: true

require "base64"
require "sorbet-runtime"

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

      if job.source.directories
        # The job.source.directory may contain globs, so we use the directories from the fetched files
        job.source.directories = decoded_dependency_files.flat_map(&:directory).uniq
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
    def all_dependency_files
      @dependency_files
    end

    sig { returns(T::Array[Dependabot::Dependency]) }
    def all_dependencies
      @dependencies.values.flatten
    end

    sig { returns(T::Array[Dependabot::DependencyFile]) }
    def dependency_files
      @dependency_files.select { |f| f.directory == @current_directory }
    end

    sig { returns(T::Array[Dependabot::Dependency]) }
    def dependencies
      T.must(@dependencies[@current_directory])
    end

    # Returns the subset of all project dependencies which are permitted
    # by the project configuration.
    sig { returns(T::Array[Dependabot::Dependency]) }
    def allowed_dependencies
      if job.security_updates_only?
        dependencies.select { |d| T.must(job.dependencies).include?(d.name) }
      else
        dependencies.select { |d| job.allowed_update?(d) }
      end
    end

    # Returns the subset of all project dependencies which are specifically
    # requested to be updated by the job definition.
    sig { returns(T::Array[Dependabot::Dependency]) }
    def job_dependencies
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
    def job_group
      return nil unless job.dependency_group_to_refresh

      @dependency_group_engine.find_group(name: T.must(job.dependency_group_to_refresh))
    end

    sig { params(dependency_names: T.any(String, T::Array[String])).void }
    def add_handled_dependencies(dependency_names)
      raise "Current directory not set" if @current_directory == ""

      set = @handled_dependencies[@current_directory] || Set.new
      set += Array(dependency_names)
      @handled_dependencies[@current_directory] = set
    end

    sig { returns(T::Set[String]) }
    def handled_dependencies
      raise "Current directory not set" if @current_directory == ""

      T.must(@handled_dependencies[@current_directory])
    end

    # rubocop:disable Performance/Sum
    sig { returns(T::Set[String]) }
    def handled_dependencies_all_directories
      T.must(@handled_dependencies.values.reduce(&:+))
    end
    # rubocop:enable Performance/Sum

    sig { params(dir: String).void }
    def current_directory=(dir)
      @current_directory = dir
      @handled_dependencies[dir] = Set.new unless @handled_dependencies.key?(dir)
    end

    sig { returns(T::Array[Dependabot::DependencyGroup]) }
    def groups
      @dependency_group_engine.dependency_groups
    end

    sig { returns(T::Array[Dependabot::Dependency]) }
    def ungrouped_dependencies
      # If no groups are defined, all dependencies are ungrouped by default.
      return allowed_dependencies unless groups.any?

      if Dependabot::Experiments.enabled?(:dependency_has_directory)
        return allowed_dependencies.reject { |dep| handled_dependencies_all_directories.include?(dep.name) }
      end

      # Otherwise return dependencies that haven't been handled during the group update portion.
      allowed_dependencies.reject { |dep| handled_dependencies.include?(dep.name) }
    end

    private

    sig do
      params(job: Dependabot::Job, base_commit_sha: String, dependency_files: T::Array[Dependabot::DependencyFile]).void
    end
    def initialize(job:, base_commit_sha:, dependency_files:) # rubocop:disable Metrics/AbcSize
      @original_directory = T.let(job.source.directory, T.nilable(String))

      @job = job
      @base_commit_sha = base_commit_sha
      @dependency_files = dependency_files
      @handled_dependencies = T.let({}, T::Hash[String, T::Set[String]])
      @current_directory = T.let("", String)

      @dependencies = T.let({}, T::Hash[String, T::Array[Dependabot::Dependency]])
      directories.each do |dir|
        @current_directory = dir
        @dependencies[dir] = parse_files!
      end

      @dependency_group_engine = T.let(DependencyGroupEngine.from_job_config(job: job),
                                       Dependabot::DependencyGroupEngine)
      directories.each do |dir|
        @current_directory = dir
        @dependency_group_engine.assign_to_groups!(dependencies: allowed_dependencies)
      end

      # The non-grouped operations depend on there being a job.source.directory, so we want to not burden it with
      # multi-dir support, yet. The rest of this method maintains multi-dir logic by setting some defaults.
      if @original_directory.nil? && @dependency_group_engine.dependency_groups.none? && job.security_updates_only?
        @original_directory = T.must(job.source.directories).first
      end

      job.source.directory = @original_directory
      return unless job.source.directory

      @current_directory = T.must(job.source.directory)
      @handled_dependencies[@current_directory] = Set.new
    end

    # Helper simplifies some of the logic, no need to check for one or the other!
    sig { returns(T::Array[String]) }
    def directories
      if @original_directory
        [@original_directory]
      else
        T.must(job.source.directories)
      end
    end

    sig { returns(Dependabot::Job) }
    attr_reader :job

    sig { returns(T::Array[Dependabot::Dependency]) }
    def parse_files!
      dependency_file_parser.parse
    end

    sig { returns(Dependabot::FileParsers::Base) }
    def dependency_file_parser
      job.source.directory = @current_directory
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
