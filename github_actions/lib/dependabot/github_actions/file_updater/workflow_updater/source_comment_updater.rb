# typed: strong
# frozen_string_literal: true

require "dependabot/github_actions/file_updater/workflow_updater"

module Dependabot
  module GithubActions
    class FileUpdater < Dependabot::FileUpdaters::Base
      class WorkflowUpdater
        class SourceCommentUpdater
          extend T::Sig

          sig do
            params(
              workflow_file: WorkflowFile,
              commenter: VersionCommenter,
              metadata_builder: WorkflowFile::MetadataBuilder,
              comment_locator: SourceCommentLocator
            ).void
          end
          def initialize(workflow_file:, commenter:, metadata_builder:, comment_locator:)
            @workflow_file = workflow_file
            @commenter = commenter
            @metadata_builder = metadata_builder
            @comment_locator = comment_locator
          end

          sig { params(update: SourceUpdate).returns(T::Array[ContentEdit]) }
          def edits_for(update)
            located_comment = located_comment_for(update)
            if located_comment
              recognized = commenter.recognized_comment?(
                located_comment.comment,
                update.old_ref,
                update.new_ref
              )
              if located_comment.syntax_adjacent || recognized
                return edits_for_existing_comment(update, located_comment, recognized)
              end
            end

            edits_for_new_comment(update)
          end

          private

          sig { returns(WorkflowFile) }
          attr_reader :workflow_file

          sig { returns(VersionCommenter) }
          attr_reader :commenter

          sig { returns(WorkflowFile::MetadataBuilder) }
          attr_reader :metadata_builder

          sig { returns(SourceCommentLocator) }
          attr_reader :comment_locator

          sig do
            params(
              update: SourceUpdate,
              located_comment: SourceCommentLocator::LocatedComment,
              recognized: T::Boolean
            ).returns(T::Array[ContentEdit])
          end
          def edits_for_existing_comment(update, located_comment, recognized)
            updated_comment = commenter.updated_comment(
              located_comment.comment,
              update.old_ref,
              update.new_ref
            )
            mapping = colliding_flow_mapping(update)
            if recognized && !located_comment.syntax_adjacent && mapping
              return relocated_mapping_comment_edits(mapping, located_comment, updated_comment)
            end

            replacement = updated_comment || (recognized ? "" : nil)
            return [] unless replacement

            [
              ContentEdit.new(
                start_offset: located_comment.start_offset,
                end_offset: located_comment.end_offset,
                replacement: replacement
              )
            ]
          end

          sig { params(update: SourceUpdate).returns(T::Array[ContentEdit]) }
          def edits_for_new_comment(update)
            new_comment = commenter.new_comment(update.old_ref, update.new_ref)
            return [] unless new_comment

            mapping_edit = colliding_flow_mapping_comment_edit(update, new_comment)
            return [mapping_edit] if mapping_edit

            line = T.must(metadata_builder.comment_anchor(update.declaration)).first
            line_end = workflow_file.line_end_offset(line)
            [ContentEdit.new(start_offset: line_end, end_offset: line_end, replacement: new_comment)]
          end

          sig { params(update: SourceUpdate).returns(T.nilable(SourceCommentLocator::LocatedComment)) }
          def located_comment_for(update)
            declaration_comment = comment_locator.for_declaration(update.declaration)
            if declaration_comment
              recognized = commenter.recognized_comment?(
                declaration_comment.comment,
                update.old_ref,
                update.new_ref
              )
              return declaration_comment if declaration_comment.syntax_adjacent || recognized
            end

            sequence = update.declaration.steps_sequence
            return unless sequence

            sequence_comment = comment_locator.for_sequence(sequence)
            return unless sequence_comment

            recognized = commenter.recognized_comment?(sequence_comment.comment, update.old_ref, update.new_ref)
            return unless sequence_comment.syntax_adjacent || recognized

            sequence_comment
          end

          sig do
            params(
              mapping: Psych::Nodes::Mapping,
              located_comment: SourceCommentLocator::LocatedComment,
              updated_comment: T.nilable(String)
            ).returns(T::Array[ContentEdit])
          end
          def relocated_mapping_comment_edits(mapping, located_comment, updated_comment)
            deletion = ContentEdit.new(
              start_offset: located_comment.start_offset,
              end_offset: located_comment.end_offset,
              replacement: ""
            )
            return [deletion] unless updated_comment

            end_offset = node_end_offset(mapping)
            indentation = " " * workflow_file.node_start_column(mapping)
            insertion = ContentEdit.new(
              start_offset: end_offset,
              end_offset: end_offset,
              replacement: "#{updated_comment}#{workflow_file.newline}#{indentation}"
            )
            [insertion, deletion]
          end

          sig { params(update: SourceUpdate, comment: String).returns(T.nilable(ContentEdit)) }
          def colliding_flow_mapping_comment_edit(update, comment)
            mapping = colliding_flow_mapping(update)
            return unless mapping

            end_offset = node_end_offset(mapping)
            indentation = " " * workflow_file.node_start_column(mapping)
            ContentEdit.new(
              start_offset: end_offset,
              end_offset: end_offset,
              replacement: "#{comment}#{workflow_file.newline}#{indentation}"
            )
          end

          sig { params(update: SourceUpdate).returns(T.nilable(Psych::Nodes::Mapping)) }
          def colliding_flow_mapping(update)
            declaration = update.declaration
            return if declaration.steps_sequence
            return unless metadata_builder.comment_line_collision?(declaration)

            mapping = declaration.mapping_node
            return unless mapping

            flow_style = T.cast(Psych::Nodes::Mapping::FLOW, Integer)
            return unless workflow_file.mapping_node_style(mapping) == flow_style

            mapping
          end

          sig { params(node: Psych::Nodes::Node).returns(Integer) }
          def node_end_offset(node)
            workflow_file.offset(
              workflow_file.node_end_line(node),
              workflow_file.node_end_column(node)
            )
          end
        end
      end
    end
  end
end
