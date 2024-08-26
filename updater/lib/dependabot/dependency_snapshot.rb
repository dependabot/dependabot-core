# typed: strict
# frozen_string_literal: true

require "base64"
require "sorbet-runtime"

require "dependabot/file_parsers"
require "dependabot/notices_helpers"

# This class describes the dependencies obtained from a project at a specific commit SHA
# including both the Dependabot::DependencyFile objects at that reference as well as
# means to parse them into a set of Dependabot::Dependency objects.
#
# This class is the input for a Dependabot::Updater process with Dependabot::DependencyChange
# representing the output.
module Dependabot
  class DependencySnapshot
    extend T::Sig
    include NoticesHelpers

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
      assert_current_directory_set!
      @dependency_files.select { |f| f.directory == @current_directory }
    end

    sig { returns(T::Array[Dependabot::Dependency]) }
    def dependencies
      assert_current_directory_set!
      T.must(@dependencies[@current_directory])
    end

    sig { returns(T.nilable(Dependabot::PackageManagerBase)) }
    def package_manager
      @package_manager[@current_directory]
    end

    sig { returns(T::Array[Dependabot::Notice]) }
    def notices
      # The notices array in dependency snapshot stay immutable,
      # so we can return a copy
      @notices[@current_directory]&.dup || []
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

    sig { params(group: Dependabot::DependencyGroup).void }
    def mark_group_handled(group)
      directories.each do |directory|
        @current_directory = directory

        # add the existing dependencies in the group so individual updates don't try to update them
        add_handled_dependencies(dependencies_in_existing_pr_for_group(group).filter_map { |d| d["dependency-name"] })
        # also add dependencies that might be in the group, as a rebase would add them;
        # this avoids individual PR creation that immediately is superseded by a group PR supersede
        add_handled_dependencies(group.dependencies.map(&:name))
      end
    end

    sig { params(dependency_names: T.any(String, T::Array[String])).void }
    def add_handled_dependencies(dependency_names)
      assert_current_directory_set!
      set = @handled_dependencies[@current_directory] || Set.new
      set += Array(dependency_names)
      @handled_dependencies[@current_directory] = set
    end

    sig { returns(T::Set[String]) }
    def handled_dependencies
      assert_current_directory_set!
      T.must(@handled_dependencies[@current_directory])
    end

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
      @package_manager = T.let({}, T::Hash[String, T.nilable(Dependabot::PackageManagerBase)])
      @notices = T.let({}, T::Hash[String, T::Array[Dependabot::Notice]])

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
      # reset to ensure we don't accidentally use it later without setting it
      @current_directory = ""
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
      assert_current_directory_set!
      job.source.directory = @current_directory
      parser = Dependabot::FileParsers.for_package_manager(job.package_manager).new(
        dependency_files: dependency_files,
        repo_contents_path: job.repo_contents_path,
        source: job.source,
        credentials: job.credentials,
        reject_external_code: job.reject_external_code?,
        options: job.experiments
      )
      # Add 'package_manager' to the depedency_snapshopt to use it in operations'
      package_manager_for_current_directory = parser.package_manager
      @package_manager[@current_directory] = package_manager_for_current_directory

      # Log deprecation notices if the package manager is deprecated
      # and add them to the notices array
      notices_for_current_directory = []

      # add deprecation notices for the package manager
      add_deprecation_notice(
        notices: notices_for_current_directory,
        package_manager: package_manager_for_current_directory
      )
      @notices[@current_directory] = notices_for_current_directory

      parser
    end

    sig { params(group: Dependabot::DependencyGroup).returns(T::Array[T::Hash[String, String]]) }
    def dependencies_in_existing_pr_for_group(group)
      job.existing_group_pull_requests.find do |pr|
        pr["dependency-group-name"] == group.name
      end&.fetch("dependencies", []) || []
    end

    sig { void }
    def assert_current_directory_set!
      if @current_directory == "" && directories.count == 1
        @current_directory = T.must(directories.first)
        return
      end

      raise DependabotError, "Assertion failed: Current directory not set" if @current_directory == ""
    end
  end
end
