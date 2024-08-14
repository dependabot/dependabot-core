# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/errors"
require "dependabot/file_updaters"
require "dependabot/file_updaters/base"

module Dependabot
  module GithubActions
    class FileUpdater < Dependabot::FileUpdaters::Base
      extend T::Sig

      sig { override.returns(T::Array[Regexp]) }
      def self.updated_files_regex
        if Dependabot::Experiments.enabled?(:allowlist_dependency_files)
          [%r{\.github/workflows?/.+\.ya?ml$}]
        else
          # Old regex. After 100% rollout of the allowlist, this will be removed.
          [%r{\.github/workflows/.+\.ya?ml$}]
        end
      end

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

        previous_version_tag = git_checker.most_specific_version_tag_for_sha(old_ref)
        return unless previous_version_tag # There's no tag for this commit

        previous_version = version_class.new(previous_version_tag).to_s
        return unless comment.end_with? previous_version

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
