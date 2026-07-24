# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/errors"
require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/github_actions/constants"
require "dependabot/github_actions/lockfile"

module Dependabot
  module GithubActions
    class FileUpdater < Dependabot::FileUpdaters::Base
      extend T::Sig

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def updated_dependency_files
        updated_files = changed_workflow_files.map do |file|
          updated_file(file: file, content: updated_workflow_file_content(file))
        end
        updated_files.concat(relocked_files)
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
      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def relocked_files
        lock = lockfile
        reader = lockfile_reader
        return [] unless lock && reader

        changed_onboarded = changed_workflow_files.select { |f| reader.onboarded?(repo_relative_path(f)) }
        return [] if changed_onboarded.empty?

        # Gate only once the lock is authoritative for a workflow we're changing, so an
        # incompatible/malformed lock over untouched workflows never blocks a legacy update.
        Lockfile::VersionGate.assert_supported!(reader.version)
        reader.validate_dependency_entries!

        # Materialize the full onboarded closure so the lock remains intact, but fix
        # only changed workflows so unrelated refs are not touched.
        content = Lockfile::CliEngine.new(credentials).relock(
          workflow_files: rewritten_onboarded_workflow_files(reader),
          lockfile: lock,
          workflow_paths: changed_onboarded.map { |file| repo_relative_path(file) }
        )

        [updated_file(file: lock, content: content)]
      end

      # The onboarded closure as the engine should see it: every workflow the lock
      # tracks, with bumped refs applied to changed ones and the rest left verbatim.
      sig { params(reader: Lockfile::Reader).returns(T::Array[Dependabot::DependencyFile]) }
      def rewritten_onboarded_workflow_files(reader)
        changed = changed_workflow_files
        onboarded_workflow_files(reader).map do |file|
          next file unless changed.include?(file)

          DependencyFile.new(
            name: file.name,
            content: updated_workflow_file_content(file),
            directory: file.directory,
            type: file.type,
            support_file: file.support_file?
          )
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

      # rubocop:disable Metrics/AbcSize
      sig { params(file: Dependabot::DependencyFile).returns(String) }
      def updated_workflow_file_content(file)
        updated_requirement_pairs =
          dependency.requirements.zip(T.must(dependency.previous_requirements))
                    .reject do |new_req, old_req|
            next true if new_req[:file] != file.name

            new_req[:source] == T.must(old_req)[:source]
          end

        updated_content = T.must(file.content)

        updated_requirement_pairs.each do |new_req, old_req|
          # TODO: Support updating Docker sources
          next unless new_req.fetch(:source).fetch(:type) == "git"

          old_ref = T.must(old_req).fetch(:source).fetch(:ref)
          new_ref = new_req.fetch(:source).fetch(:ref)

          old_declaration = T.must(old_req).fetch(:metadata).fetch(:declaration_string)
          new_declaration =
            old_declaration
            .gsub(/@.*+/, "@#{new_ref}")

          # Replace the old declaration that's preceded by a non-word character (unless it's a hyphen)
          # and followed by a whitespace character (comments) or EOL.
          # If the declaration is followed by a comment that lists the version associated
          # with the SHA source ref, then update the comment to the human-readable new version.
          # However, if the comment includes additional text beyond the version, for safety
          # we skip updating the comment in case it's a custom note, todo, warning etc of some kind.
          # See the related unit tests for examples.
          updated_content =
            updated_content
            .gsub(
              /(?<=[^a-zA-Z_-]|"|')#{Regexp.escape(old_declaration)}["']?(?<comment>\s+#.*)?(?=\s|$)/
            ) do |match|
              comment = Regexp.last_match(:comment)
              match.gsub!(old_declaration, new_declaration)
              if comment && (updated_comment = updated_version_comment(comment, old_ref, new_ref))
                match.gsub!(comment, updated_comment)
              end
              match
            end
        end

        updated_content
      end
      # rubocop:enable Metrics/AbcSize

      sig { params(comment: T.nilable(String), old_ref: String, new_ref: String).returns(T.nilable(String)) }
      def updated_version_comment(comment, old_ref, new_ref)
        raise "No comment!" unless comment

        comment = comment.rstrip
        git_checker = Dependabot::GitCommitChecker.new(dependency: dependency, credentials: credentials)
        return unless git_checker.ref_looks_like_commit_sha?(old_ref)

        previous_version_tags = git_checker.most_specific_version_tags_for_sha(old_ref)
        return unless previous_version_tags.any? # There's no tag for this commit

        # Use the most specific (longest) matching version to avoid partial replacements.
        # Tags are sorted ascending, so ["v1", "v1.0", "v1.0.1"] maps to ["1", "1.0", "1.0.1"].
        # Without this, "1" could match the end of "v1.0.1", causing gsub("1", "1.1") => "v1.1.0.1.1".
        previous_version = previous_version_tags.map { |tag| version_class.new(tag).to_s }
                                                .select { |version| comment.end_with?(version) }
                                                .max_by(&:length)
        return unless previous_version

        new_version_tag = git_checker.most_specific_version_tag_for_sha(new_ref)
        return unless new_version_tag

        new_version = version_class.new(new_version_tag).to_s
        comment.gsub(previous_version, new_version)
      end

      sig { returns(T.class_of(Dependabot::GithubActions::Version)) }
      def version_class
        GithubActions::Version
      end
    end
  end
end

Dependabot::FileUpdaters
  .register("github_actions", Dependabot::GithubActions::FileUpdater)
