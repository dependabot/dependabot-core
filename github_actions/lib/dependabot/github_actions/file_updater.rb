# frozen_string_literal: true

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/errors"

module Dependabot
  module GithubActions
    class FileUpdater < Dependabot::FileUpdaters::Base
      def self.updated_files_regex
        [%r{\.github/workflows/.+\.ya?ml$}]
      end

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

      def dependency
        # GitHub Actions will only ever be updating a single dependency
        dependencies.first
      end

      def check_required_files
        # Just check if there are any files at all.
        return if dependency_files.any?

        raise "No workflow files!"
      end

      def updated_workflow_file_content(file)
        updated_requirement_pairs =
          dependency.requirements.zip(dependency.previous_requirements).
          reject do |new_req, old_req|
            next true if new_req[:file] != file.name

            new_req[:source] == old_req[:source]
          end

        updated_content = file.content

        updated_requirement_pairs.each do |new_req, old_req|
          # TODO: Support updating Docker sources
          next unless new_req.fetch(:source).fetch(:type) == "git"

          old_declaration = old_req.fetch(:metadata).fetch(:declaration_string)
          new_declaration =
            old_declaration.
            gsub(/@.*+/, "@#{new_req.fetch(:source).fetch(:ref)}")

          # Replace the old declaration that's preceded by a non-word character
          # and followed by a whitespace character (comments) or EOL.
          # If the declaration is followed by a comment, attempt to update
          # any version comments associated with SHA source refs.
          updated_content =
            updated_content.
            gsub(
              /(?<=\W|"|')#{Regexp.escape(old_declaration)}(?<comment>\s+#.*)?(?=\s|"|'|$)/
            ) do |match|
              comment = Regexp.last_match(:comment)
              match.gsub!(old_declaration, new_declaration)
              if comment && (updated_comment = updated_version_comment(comment, new_req))
                match.gsub!(comment, updated_comment)
              end
              match
            end
        end

        updated_content
      end

      def updated_version_comment(comment, new_req)
        raise "No comment!" unless comment
        comment = comment.rstrip
        return unless dependency.previous_version && dependency.version
        return unless comment.end_with? dependency.previous_version

        git_checker = Dependabot::GitCommitChecker.new(dependency: dependency, credentials: credentials)
        return unless git_checker.ref_looks_like_commit_sha?(new_req.fetch(:source).fetch(:ref))

        comment.gsub(dependency.previous_version, dependency.version)
      end
    end
  end
end

Dependabot::FileUpdaters.
  register("github_actions", Dependabot::GithubActions::FileUpdater)
