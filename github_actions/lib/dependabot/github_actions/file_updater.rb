# typed: strong
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
        updated_requirement_pairs =
          dependency.requirements.zip(T.must(dependency.previous_requirements))
                    .reject do |new_req, old_req|
            next true if new_req.file != file.name

            new_req.source == T.must(old_req).source
          end

        updated_content = T.must(file.content)

        updated_requirement_pairs.each do |new_req, old_req|
          # TODO: Support updating Docker sources
          next unless new_req.source_string("type") == "git"

          old_ref = T.must(T.must(old_req).source_string("ref"))
          new_ref = T.must(new_req.source_string("ref"))

          old_declaration = T.must(T.must(old_req).metadata_string("declaration_string"))
          new_declaration =
            old_declaration
            .gsub(/@.*+/, "@#{new_ref}")
          declaration_pattern = uses_declaration_pattern(old_declaration)

          # Include the rest of the line so a new comment is appended after any
          # flow-style mapping syntax, rather than inside the mapping.
          updated_content =
            updated_content
            .gsub(
              /#{declaration_pattern}(?<suffix>[^\r\n]*)/
            ) do |match|
              updated_workflow_line(
                match: match,
                comment: trailing_yaml_comment(T.must(Regexp.last_match(:suffix))),
                declaration_pattern: declaration_pattern,
                old_declaration: old_declaration,
                new_declaration: new_declaration,
                old_ref: old_ref,
                new_ref: new_ref
              )
            end
        end
        updated_content
      end

      sig { params(declaration: String).returns(Regexp) }
      def uses_declaration_pattern(declaration)
        escaped_declaration = Regexp.escape(declaration)

        /
          (?:^|[ \t{,])
          (?:"uses"|'uses'|uses)[ \t]*:[ \t]*
          (?:"#{escaped_declaration}"|'#{escaped_declaration}'|#{escaped_declaration})
          (?=[ \t]|$|[,}\]])
        /x
      end

      sig do
        params(
          match: String,
          comment: T.nilable(String),
          declaration_pattern: Regexp,
          old_declaration: String,
          new_declaration: String,
          old_ref: String,
          new_ref: String
        ).returns(String)
      end
      def updated_workflow_line(
        match:,
        comment:,
        declaration_pattern:,
        old_declaration:,
        new_declaration:,
        old_ref:,
        new_ref:
      )
        line_without_comment = comment ? match.delete_suffix(comment) : match
        updated_match = line_without_comment.gsub(declaration_pattern) do |declaration|
          declaration.sub(old_declaration, new_declaration)
        end

        if comment
          updated_match << (updated_version_comment(comment, old_ref, new_ref) || comment)
        elsif (new_comment = new_version_comment(old_ref, new_ref))
          updated_match << new_comment
        end
        updated_match
      end

      sig { params(suffix: String).returns(T.nilable(String)) }
      def trailing_yaml_comment(suffix)
        previous_non_whitespace = T.let(nil, T.nilable(String))
        index = 0

        while index < suffix.length
          character = T.must(suffix[index])

          if quoted_scalar_start?(character, previous_non_whitespace)
            previous_non_whitespace = character
            index = quoted_scalar_end(suffix, index)
            next
          end
          return comment_with_leading_whitespace(suffix, index) if yaml_comment_start?(suffix, index)

          previous_non_whitespace = character unless character.match?(/\s/)
          index += 1
        end

        nil
      end

      sig { params(character: String, previous_non_whitespace: T.nilable(String)).returns(T::Boolean) }
      def quoted_scalar_start?(character, previous_non_whitespace)
        return false unless character == "'" || character == '"'

        previous_non_whitespace.nil? || ":,[{?-".include?(previous_non_whitespace)
      end

      sig { params(suffix: String, quote_index: Integer).returns(Integer) }
      def quoted_scalar_end(suffix, quote_index)
        quote = T.must(suffix[quote_index])
        index = quote_index + 1

        while index < suffix.length
          character = T.must(suffix[index])
          if quote == "'" && character == "'" && suffix[index + 1] == "'"
            index += 2
          elsif quote == '"' && character == "\\"
            index += 2
          elsif character == quote
            return index + 1
          else
            index += 1
          end
        end

        suffix.length
      end

      sig { params(suffix: String, index: Integer).returns(T::Boolean) }
      def yaml_comment_start?(suffix, index)
        suffix[index] == "#" && index.positive? && T.must(suffix[index - 1]).match?(/\s/)
      end

      sig { params(suffix: String, hash_index: Integer).returns(String) }
      def comment_with_leading_whitespace(suffix, hash_index)
        comment_start = hash_index
        comment_start -= 1 while comment_start.positive? && T.must(suffix[comment_start - 1]).match?(/\s/)
        T.must(suffix[comment_start..])
      end

      sig { params(comment: T.nilable(String), old_ref: String, new_ref: String).returns(T.nilable(String)) }
      def updated_version_comment(comment, old_ref, new_ref)
        raise "No comment!" unless comment

        comment = comment.rstrip
        previous_version = previous_version_from_comment(comment, old_ref, new_ref)
        return unless previous_version

        new_version_tag = git_checker.most_specific_version_tag_for_sha(new_ref)
        return unless new_version_tag

        new_version = version_class.new(new_version_tag).to_s
        comment.gsub(previous_version, new_version)
      end

      sig { params(comment: String, old_ref: String, new_ref: String).returns(T.nilable(String)) }
      def previous_version_from_comment(comment, old_ref, new_ref)
        version_tags = if git_checker.ref_looks_like_commit_sha?(old_ref)
                         git_checker.most_specific_version_tags_for_sha(old_ref)
                       elsif tag_to_sha?(old_ref, new_ref)
                         version_tags_for_ref(old_ref)
                       else
                         []
                       end

        # Prefer the longest matching version so "1" does not partially replace "1.0.1".
        version_tags
          .filter_map { |tag| version_class.new(tag).to_s if version_class.correct?(tag) }
          .select { |version| comment.end_with?(version) }
          .max_by(&:length)
      end

      sig { params(ref: String).returns(T::Array[String]) }
      def version_tags_for_ref(ref)
        tags = [ref]
        commit_sha = git_checker.head_commit_for_local_branch(ref)
        tags.concat(git_checker.most_specific_version_tags_for_sha(commit_sha)) if commit_sha
        tags.uniq
      end

      sig { params(old_ref: String, new_ref: String).returns(T.nilable(String)) }
      def new_version_comment(old_ref, new_ref)
        return unless tag_to_sha?(old_ref, new_ref)

        new_version_tag = git_checker.most_specific_version_tag_for_sha(new_ref)
        return unless new_version_tag

        " # #{new_version_tag}"
      end

      sig { params(old_ref: String, new_ref: String).returns(T::Boolean) }
      def tag_to_sha?(old_ref, new_ref)
        version_class.correct?(old_ref) && git_checker.ref_looks_like_commit_sha?(new_ref)
      end

      sig { returns(Dependabot::GitCommitChecker) }
      def git_checker
        @git_checker ||= T.let(
          Dependabot::GitCommitChecker.new(dependency: dependency, credentials: credentials),
          T.nilable(Dependabot::GitCommitChecker)
        )
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
