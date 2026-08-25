# typed: strict
# frozen_string_literal: true

require "dependabot/github_actions/file_updater"

module Dependabot
  module GithubActions
    class FileUpdater < Dependabot::FileUpdaters::Base
      class WorkflowUpdater
        extend T::Sig

        class SourceUpdate < T::Struct
          const :declaration, WorkflowFile::UsesDeclaration
          const :old_declaration, String
          const :new_declaration, String
          const :old_ref, String
          const :new_ref, String
        end

        class ContentEdit < T::Struct
          const :start_offset, Integer
          const :end_offset, Integer
          const :replacement, String
        end

        require_relative "workflow_updater/version_commenter"
        require_relative "workflow_updater/yaml_comment_finder"
        require_relative "workflow_updater/flow_sequence_comments"
        require_relative "workflow_updater/source_updater"

        sig do
          params(
            file: Dependabot::DependencyFile,
            dependency: Dependabot::Dependency,
            commenter: VersionCommenter
          ).void
        end
        def initialize(file:, dependency:, commenter:)
          @file = file
          @dependency = dependency
          @commenter = commenter
          @comment_finder = T.let(YamlCommentFinder.new, YamlCommentFinder)
        end

        sig { returns(String) }
        def updated_content
          workflow_file = WorkflowFile.new(T.must(file.content))
          source_updates, fallback_pairs = requirement_updates(workflow_file)

          content = SourceUpdater.new(
            workflow_file: workflow_file,
            updates: source_updates,
            commenter: commenter,
            comment_finder: comment_finder
          ).updated_content
          fallback_pairs.each do |new_req, old_req|
            content = apply_text_update(content, new_req, old_req)
          end
          content
        end

        private

        sig { returns(Dependabot::DependencyFile) }
        attr_reader :file

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(VersionCommenter) }
        attr_reader :commenter

        sig { returns(YamlCommentFinder) }
        attr_reader :comment_finder

        sig do
          params(workflow_file: WorkflowFile).returns(
            [
              T::Array[SourceUpdate],
              T::Array[[Dependabot::DependencyRequirement, Dependabot::DependencyRequirement]]
            ]
          )
        end
        def requirement_updates(workflow_file)
          source_updates = T.let([], T::Array[SourceUpdate])
          fallback_pairs = T.let(
            [],
            T::Array[[Dependabot::DependencyRequirement, Dependabot::DependencyRequirement]]
          )

          dependency.requirements.zip(T.must(dependency.previous_requirements)).each do |new_req, old_req|
            previous_requirement = T.must(old_req)
            next if new_req.file != file.name || new_req.source == previous_requirement.source
            next unless new_req.source_string("type") == "git"

            source_update = source_update_for(workflow_file, new_req, previous_requirement)
            source_update ? source_updates << source_update : fallback_pairs << [new_req, previous_requirement]
          end

          [source_updates, fallback_pairs]
        end

        sig do
          params(
            workflow_file: WorkflowFile,
            new_req: Dependabot::DependencyRequirement,
            old_req: Dependabot::DependencyRequirement
          ).returns(T.nilable(SourceUpdate))
        end
        def source_update_for(workflow_file, new_req, old_req)
          path = yaml_source_path(old_req)
          return unless path

          declaration = workflow_file.declaration_at(path)
          return unless declaration
          return unless declaration.value_node && declaration.source_node && declaration.mapping_node

          old_declaration = T.must(old_req.metadata_string("declaration_string"))
          new_ref = T.must(new_req.source_string("ref"))
          SourceUpdate.new(
            declaration: declaration,
            old_declaration: old_declaration,
            new_declaration: old_declaration.gsub(/@.*+/, "@#{new_ref}"),
            old_ref: T.must(old_req.source_string("ref")),
            new_ref: new_ref
          )
        end

        sig { params(requirement: Dependabot::DependencyRequirement).returns(T.nilable(WorkflowFile::Path)) }
        def yaml_source_path(requirement)
          metadata = requirement.metadata
          return unless metadata

          raw_source = metadata[:yaml_source] || metadata["yaml_source"]
          return unless raw_source.is_a?(Hash)

          raw_path = raw_source[:path] || raw_source["path"]
          return unless raw_path.is_a?(Array)
          return unless raw_path.all? { |part| part.is_a?(String) || part.is_a?(Integer) }

          path = T.let([], WorkflowFile::Path)
          raw_path.each { |part| path << part }
          path
        end

        sig do
          params(
            content: String,
            new_req: Dependabot::DependencyRequirement,
            old_req: Dependabot::DependencyRequirement
          ).returns(String)
        end
        def apply_text_update(content, new_req, old_req)
          old_ref = T.must(old_req.source_string("ref"))
          new_ref = T.must(new_req.source_string("ref"))
          old_declaration = T.must(old_req.metadata_string("declaration_string"))
          new_declaration = old_declaration.gsub(/@.*+/, "@#{new_ref}")
          declaration_pattern = uses_declaration_pattern(old_declaration)

          content.gsub(/#{declaration_pattern}(?<suffix>[^\r\n]*)/) do |match|
            updated_workflow_line(
              match: match,
              comment: comment_finder.find(T.must(Regexp.last_match(:suffix))),
              declaration_pattern: declaration_pattern,
              old_declaration: old_declaration,
              new_declaration: new_declaration,
              old_ref: old_ref,
              new_ref: new_ref
            )
          end
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
            updated_match << (commenter.updated_comment(comment, old_ref, new_ref) || comment)
          elsif (new_comment = commenter.new_comment(old_ref, new_ref))
            updated_match << new_comment
          end
          updated_match
        end
      end
    end
  end
end
