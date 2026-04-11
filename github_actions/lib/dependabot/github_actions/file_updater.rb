# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/errors"
require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/github_actions/constants"

module Dependabot
  module GithubActions
    class FileUpdater < Dependabot::FileUpdaters::Base
      extend T::Sig

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def updated_dependency_files
        updated_files = []

        dependency_files.each do |file|
          next unless requirement_changed?(file, dependency)

          updated_files <<
            updated_file(
              file: file,
              content: updated_workflow_file_content(file)
            )
        end

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
              elsif !comment && (new_comment = new_version_comment(old_ref, new_ref))
                match << new_comment
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

        previous_version = previous_version_from_comment(comment, old_ref, new_ref)
        return unless previous_version

        new_version_tag = git_checker.most_specific_version_tag_for_sha(new_ref)
        return unless new_version_tag

        new_version = version_class.new(new_version_tag).to_s
        comment.gsub(previous_version, new_version)
      end

      sig { params(comment: String, old_ref: String, new_ref: String).returns(T.nilable(String)) }
      def previous_version_from_comment(comment, old_ref, new_ref)
        if git_checker.ref_looks_like_commit_sha?(old_ref)
          # SHA→SHA: resolve version from old SHA
          previous_version_tags = git_checker.most_specific_version_tags_for_sha(old_ref)
          return unless previous_version_tags.any?

          # Use the most specific (longest) matching version to avoid partial replacements.
          # Tags are sorted ascending, so ["v1", "v1.0", "v1.0.1"] maps to ["1", "1.0", "1.0.1"].
          # Without this, "1" could match the end of "v1.0.1", causing gsub("1", "1.1") => "v1.1.0.1.1".
          previous_version_tags.map { |tag| version_class.new(tag).to_s }
                               .select { |version| comment.end_with?(version) }
                               .max_by(&:length)
        elsif version_class.correct?(old_ref) && git_checker.ref_looks_like_commit_sha?(new_ref)
          # Tag→SHA: derive version from old ref directly
          old_version = version_class.new(old_ref).to_s
          old_version if comment.end_with?(old_version)
        end
      end

      # Generates a version comment when transitioning from a version tag to a SHA pin.
      sig { params(old_ref: String, new_ref: String).returns(T.nilable(String)) }
      def new_version_comment(old_ref, new_ref)
        return unless version_class.correct?(old_ref)
        return unless git_checker.ref_looks_like_commit_sha?(new_ref)

        new_version_tag = git_checker.most_specific_version_tag_for_sha(new_ref)
        return unless new_version_tag

        " # #{new_version_tag}"
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
