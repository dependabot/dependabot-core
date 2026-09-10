# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/errors"
require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/github_actions/constants"
require "dependabot/github_actions/lockfile"
require "dependabot/github_actions/workflow_file"

module Dependabot
  module GithubActions
    class FileUpdater < Dependabot::FileUpdaters::Base
      extend T::Sig

      require_relative "file_updater/workflow_updater"

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def updated_dependency_files
        updated_files = changed_workflow_files.map do |file|
          updated_file(file: file, content: updated_workflow_file_content(file))
        end
        updated_files.concat(relocked_files(updated_files))
        updated_files.reject! { |f| dependency_files.include?(f) }
        raise "No files changed!" if updated_files.none?

        updated_files
      end

      private

      sig { returns(Dependabot::Dependency) }
      def dependency
        # GitHub Actions will only ever be updating a single dependency
        T.must(dependencies.first)
      end

      sig { override.void }
      def check_required_files
        # Just check if there are any files at all.
        return if dependency_files.any?

        raise "No workflow files!"
      end

      # Workflow files (everything except the lockfile) whose requirement changed.
      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def changed_workflow_files
        dependency_files
          .reject { |f| lockfile?(f) }
          .select { |f| requirement_changed?(f, dependency) }
      end

      # When the repo has an `actions.lock` authoritative for one or more changed
      # workflows, regenerate it through the gh-actions-lock engine. Lock keys and
      # onboarding comparisons are repo-relative paths, independent of the Dependabot
      # `directory`. Workflows absent from the lock (and lockless repos) never reach
      # here, preserving today's regex-only behavior.
      sig do
        params(updated_workflow_files: T::Array[Dependabot::DependencyFile])
          .returns(T::Array[Dependabot::DependencyFile])
      end
      def relocked_files(updated_workflow_files)
        changed_repository_workflows = changed_workflow_files.select do |file|
          File.dirname(repo_relative_path(file)) == WORKFLOW_DIRECTORY
        end
        return [] if changed_repository_workflows.empty?

        lock = lockfile
        reader = lockfile_reader
        return [] unless lock && reader

        changed_onboarded = changed_repository_workflows.select { |f| reader.onboarded?(repo_relative_path(f)) }
        return [] if changed_onboarded.empty?

        # Gate only once the lock is authoritative for a workflow we're changing, so an
        # incompatible/malformed lock over untouched workflows never blocks a legacy update.
        Lockfile::VersionGate.assert_supported!(reader.version)
        reader.validate_dependency_entries!

        # Materialize the full onboarded closure so the lock remains intact, but fix
        # only changed workflows so unrelated refs are not touched.
        content = Lockfile::CliEngine.new(credentials).relock(
          workflow_files: rewritten_onboarded_workflow_files(reader, updated_workflow_files),
          lockfile: lock,
          workflow_paths: changed_onboarded.map { |file| repo_relative_path(file) }
        )

        [updated_file(file: lock, content: content)]
      end

      # The onboarded closure as the engine should see it: every workflow the lock
      # tracks, with bumped refs applied to changed ones and the rest left verbatim.
      sig do
        params(
          reader: Lockfile::Reader,
          updated_workflow_files: T::Array[Dependabot::DependencyFile]
        ).returns(T::Array[Dependabot::DependencyFile])
      end
      def rewritten_onboarded_workflow_files(reader, updated_workflow_files)
        updated_by_path = updated_workflow_files.to_h { |file| [repo_relative_path(file), file] }
        onboarded_workflow_files(reader).map do |file|
          updated_by_path.fetch(repo_relative_path(file), file)
        end
      end

      # All workflow files the lock is authoritative for (changed or not).
      sig { params(reader: Lockfile::Reader).returns(T::Array[Dependabot::DependencyFile]) }
      def onboarded_workflow_files(reader)
        dependency_files
          .reject { |f| lockfile?(f) }
          .select { |f| reader.onboarded?(repo_relative_path(f)) }
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def lockfile
        dependency_files.find { |f| lockfile?(f) }
      end

      sig { returns(T.nilable(Lockfile::Reader)) }
      def lockfile_reader
        return @lockfile_reader if defined?(@lockfile_reader)

        @lockfile_reader = T.let(
          Lockfile::Reader.from_files(dependency_files),
          T.nilable(Lockfile::Reader)
        )
      end

      sig { params(file: Dependabot::DependencyFile).returns(T::Boolean) }
      def lockfile?(file)
        repo_relative_path(file) == LOCKFILE_PATH
      end

      # Repo-relative path (no leading slash), independent of the configured
      # Dependabot directory. This is the canonical form lock keys use.
      sig { params(file: Dependabot::DependencyFile).returns(String) }
      def repo_relative_path(file)
        file.path.delete_prefix("/")
      end

      sig { params(file: Dependabot::DependencyFile).returns(String) }
      def updated_workflow_file_content(file)
        WorkflowUpdater.new(
          file: file,
          dependency: dependency,
          commenter: version_commenter
        ).updated_content
      end

      sig { returns(WorkflowUpdater::VersionCommenter) }
      def version_commenter
        @version_commenter ||= T.let(
          WorkflowUpdater::VersionCommenter.new(
            dependency: dependency,
            credentials: credentials
          ),
          T.nilable(WorkflowUpdater::VersionCommenter)
        )
      end
    end
  end
end

Dependabot::FileUpdaters
  .register("github_actions", Dependabot::GithubActions::FileUpdater)
