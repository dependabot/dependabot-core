# typed: strict
# frozen_string_literal: true

require "dependabot/github_actions/file_updater/workflow_updater"

module Dependabot
  module GithubActions
    class FileUpdater < Dependabot::FileUpdaters::Base
      class WorkflowUpdater
        class FlowSequenceComments
          extend T::Sig

          class ItemComments < T::Struct
            extend T::Sig

            const :trailing, T.nilable(String)
            const :standalone, T::Array[String]

            sig { returns(T::Boolean) }
            def any?
              !trailing.nil? || standalone.any?
            end
          end

          sig do
            params(
              workflow_file: WorkflowFile,
              sequence: Psych::Nodes::Sequence,
              commenter: VersionCommenter,
              comment_finder: YamlCommentFinder,
              item_indent: String
            ).void
          end
          def initialize(workflow_file:, sequence:, commenter:, comment_finder:, item_indent:)
            @workflow_file = workflow_file
            @sequence = sequence
            @commenter = commenter
            @comment_finder = comment_finder
            @item_indent = item_indent
            @source_comments = T.let(build_source_comments, T::Hash[Integer, ItemComments])
          end

          sig { params(index: Integer, updates: T::Array[SourceUpdate]).returns(ItemComments) }
          def rendered_for(index, updates)
            source_comments = @source_comments.fetch(index, ItemComments.new(trailing: nil, standalone: []))
            return generated_comments(updates) unless source_comments.any?

            ItemComments.new(
              trailing: process_comment(source_comments.trailing, updates, trailing: true),
              standalone: source_comments.standalone.filter_map do |comment|
                process_comment(comment, updates, trailing: false)
              end
            )
          end

          sig do
            params(
              index: Integer,
              item_count: Integer,
              source: String,
              updates: T::Array[SourceUpdate]
            ).returns(String)
          end
          def render_item(index:, item_count:, source:, updates:)
            comments = rendered_for(index, updates)
            comma = index == item_count - 1 ? "" : ","
            line = "#{item_indent}#{source}#{comma}#{comments.trailing}"
            standalone = comments.standalone.map { |comment| "#{item_indent}#{comment}" }
            ([line] + standalone).join(workflow_file.newline)
          end

          sig { params(updates: T::Array[SourceUpdate]).returns(T.nilable(ContentEdit)) }
          def trailing_comment_edit(updates)
            line = workflow_file.node_end_line(sequence)
            column = workflow_file.node_end_column(sequence)
            suffix = workflow_file.line_body(line).byteslice(workflow_file.byte_column(line, column)..) || ""
            comment = comment_finder.find(suffix)
            return unless comment
            return unless updates.any? do |update|
              commenter.recognized_comment?(comment, update.old_ref, update.new_ref)
            end

            relative_start = T.must(suffix.b.index(comment.b))
            start_offset = workflow_file.offset(line, column) + relative_start
            ContentEdit.new(
              start_offset: start_offset,
              end_offset: start_offset + comment.bytesize,
              replacement: ""
            )
          end

          private

          sig { returns(WorkflowFile) }
          attr_reader :workflow_file

          sig { returns(Psych::Nodes::Sequence) }
          attr_reader :sequence

          sig { returns(VersionCommenter) }
          attr_reader :commenter

          sig { returns(YamlCommentFinder) }
          attr_reader :comment_finder

          sig { returns(String) }
          attr_reader :item_indent

          sig { returns(T::Hash[Integer, ItemComments]) }
          def build_source_comments
            children = workflow_file.node_children(sequence)
            closing_offset = closing_bracket_offset

            children.each_with_index.to_h do |child, index|
              gap_end = children[index + 1] ? node_start_offset(T.must(children[index + 1])) : closing_offset
              gap = workflow_file.content.byteslice(node_end_offset(child)...gap_end) || ""
              [index, comments_from_gap(gap)]
            end
          end

          sig { params(gap: String).returns(ItemComments) }
          def comments_from_gap(gap)
            lines = gap.lines
            first_line = lines.shift || gap
            trailing = find_comment(first_line, trailing: true)
            standalone = lines.filter_map { |line| find_comment(line, trailing: false) }

            ItemComments.new(trailing: trailing, standalone: standalone)
          end

          sig { params(line: String, trailing: T::Boolean).returns(T.nilable(String)) }
          def find_comment(line, trailing:)
            body = line.delete_suffix("\n").delete_suffix("\r")
            comment = comment_finder.find(body)
            return unless comment

            trailing ? " #{comment.lstrip}" : comment.lstrip
          end

          sig do
            params(
              comment: T.nilable(String),
              updates: T::Array[SourceUpdate],
              trailing: T::Boolean
            ).returns(T.nilable(String))
          end
          def process_comment(comment, updates, trailing:)
            return unless comment

            index = 0
            while index < updates.length
              update = T.must(updates[index])
              updated = commenter.updated_comment(comment, update.old_ref, update.new_ref)
              return normalize_comment(updated, trailing: trailing) if updated
              return if commenter.recognized_comment?(comment, update.old_ref, update.new_ref)

              index += 1
            end

            normalize_comment(comment, trailing: trailing)
          end

          sig { params(comment: String, trailing: T::Boolean).returns(String) }
          def normalize_comment(comment, trailing:)
            trailing ? " #{comment.lstrip}" : comment.lstrip
          end

          sig { params(updates: T::Array[SourceUpdate]).returns(ItemComments) }
          def generated_comments(updates)
            comments = updates.filter_map { |update| commenter.comment_for_ref(update.new_ref) }.uniq
            raise "Conflicting version comments for one workflow step" if comments.length > 1

            ItemComments.new(trailing: comments.first, standalone: [])
          end

          sig { returns(Integer) }
          def closing_bracket_offset
            source = workflow_file.node_source(sequence)
            closing_bracket = T.must(source.b.rindex("]"))
            node_start_offset(sequence) + closing_bracket
          end

          sig { params(node: Psych::Nodes::Node).returns(Integer) }
          def node_start_offset(node)
            workflow_file.offset(
              workflow_file.node_start_line(node),
              workflow_file.node_start_column(node)
            )
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
