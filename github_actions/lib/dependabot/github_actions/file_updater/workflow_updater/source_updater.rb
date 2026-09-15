# typed: strict
# frozen_string_literal: true

require "dependabot/github_actions/file_updater/workflow_updater"

module Dependabot
  module GithubActions
    class FileUpdater < Dependabot::FileUpdaters::Base
      class WorkflowUpdater
        class SourceUpdater
          extend T::Sig

          sig do
            params(
              workflow_file: WorkflowFile,
              updates: T::Array[SourceUpdate],
              commenter: VersionCommenter,
              comment_finder: YamlCommentFinder
            ).void
          end
          def initialize(workflow_file:, updates:, commenter:, comment_finder:)
            @workflow_file = workflow_file
            @updates = updates
            @commenter = commenter
            @metadata_builder = T.let(WorkflowFile::MetadataBuilder.new(workflow_file), WorkflowFile::MetadataBuilder)
            @comment_locator = T.let(
              SourceCommentLocator.new(
                workflow_file: workflow_file,
                comment_finder: comment_finder,
                metadata_builder: @metadata_builder
              ),
              SourceCommentLocator
            )
            @comment_updater = T.let(
              SourceCommentUpdater.new(
                workflow_file: workflow_file,
                commenter: commenter,
                metadata_builder: @metadata_builder,
                comment_locator: @comment_locator
              ),
              SourceCommentUpdater
            )
          end

          sig { returns(String) }
          def updated_content
            return workflow_file.content if updates.empty?

            sequence_updates = grouped_flow_sequence_updates
            edits = sequence_updates.flat_map do |sequence, grouped_updates|
              expanded_flow_sequence_edits(sequence, grouped_updates)
            end

            updates.each do |update|
              sequence = expanded_sequence_for_update(sequence_updates, update)
              source_node = T.must(update.declaration.source_node)
              source_in_expanded_sequence = sequence_updates.keys.any? do |expanded_sequence|
                node_within?(source_node, expanded_sequence)
              end
              edits << source_value_edit(update) unless source_in_expanded_sequence

              next if sequence

              edits.concat(comment_updater.edits_for(update))
            end

            apply_content_edits(edits)
          end

          private

          sig { returns(WorkflowFile) }
          attr_reader :workflow_file

          sig { returns(T::Array[SourceUpdate]) }
          attr_reader :updates

          sig { returns(VersionCommenter) }
          attr_reader :commenter

          sig { returns(WorkflowFile::MetadataBuilder) }
          attr_reader :metadata_builder

          sig { returns(SourceCommentLocator) }
          attr_reader :comment_locator

          sig { returns(SourceCommentUpdater) }
          attr_reader :comment_updater

          sig { returns(T::Hash[Psych::Nodes::Sequence, T::Array[SourceUpdate]]) }
          def grouped_flow_sequence_updates
            sequences = updates.flat_map { |update| sequences_to_expand(update) }
            groups = T.let({}, T::Hash[Psych::Nodes::Sequence, T::Array[SourceUpdate]])
            sequences.uniq.each { |sequence| groups[sequence] = [] }

            updates.each do |update|
              sequence = update.declaration.steps_sequence
              T.must(groups[sequence]) << update if sequence && groups.key?(sequence)
            end
            groups
          end

          sig { params(update: SourceUpdate).returns(T::Array[Psych::Nodes::Sequence]) }
          def sequences_to_expand(update)
            return [] unless commenter.sha?(update.new_ref)

            sequences = metadata_builder.collision_sequences_for(update.declaration)
            collision = metadata_builder.comment_line_collision?(update.declaration)
            own_sequence = update.declaration.steps_sequence
            sequence_comment = sequence_comment_requires_expansion?(update)
            sequences << own_sequence if own_sequence && sequence_comment
            return [] unless collision || sequence_comment

            sequences.uniq.select do |sequence|
              workflow_file.sequence_node_style(sequence) == Psych::Nodes::Sequence::FLOW
            end
          end

          sig { params(update: SourceUpdate).returns(T::Boolean) }
          def sequence_comment_requires_expansion?(update)
            sequence = update.declaration.steps_sequence
            return false unless sequence

            located_comment = comment_locator.for_sequence(sequence)
            return false unless located_comment

            commenter.recognized_comment?(located_comment.comment, update.old_ref, update.new_ref)
          end

          sig do
            params(
              sequence_updates: T::Hash[Psych::Nodes::Sequence, T::Array[SourceUpdate]],
              update: SourceUpdate
            ).returns(T.nilable(Psych::Nodes::Sequence))
          end
          def expanded_sequence_for_update(sequence_updates, update)
            sequence_updates.each do |sequence, grouped_updates|
              return sequence if grouped_updates.include?(update)
            end
            nil
          end

          sig do
            params(
              sequence: Psych::Nodes::Sequence,
              grouped_updates: T::Array[SourceUpdate]
            ).returns(T::Array[ContentEdit])
          end
          def expanded_flow_sequence_edits(sequence, grouped_updates)
            key_node = T.must(workflow_file.steps_key_node_for(sequence))
            children = workflow_file.node_children(sequence)
            item_indent = " " * (workflow_file.node_start_column(key_node) + 2)
            closing_indent = " " * workflow_file.node_start_column(key_node)
            sequence_comments = FlowSequenceComments.new(
              workflow_file: workflow_file,
              sequence: sequence,
              commenter: commenter,
              comment_locator: comment_locator,
              item_indent: item_indent
            )
            trailing_comment_edit = sequence_comments.claim_trailing_comment(grouped_updates)

            lines = sequence_comments.leading_lines + children.each_with_index.map do |child, index|
              render_flow_sequence_child(
                child,
                index,
                children.length,
                grouped_updates,
                sequence_comments
              )
            end

            edits = [
              ContentEdit.new(
                start_offset: node_start_offset(sequence),
                end_offset: node_end_offset(sequence),
                replacement: flow_sequence_replacement(sequence, lines, closing_indent)
              )
            ]
            edits << trailing_comment_edit if trailing_comment_edit
            edits
          end

          sig do
            params(
              child: Psych::Nodes::Node,
              index: Integer,
              item_count: Integer,
              grouped_updates: T::Array[SourceUpdate],
              sequence_comments: FlowSequenceComments
            ).returns(String)
          end
          def render_flow_sequence_child(
            child,
            index,
            item_count,
            grouped_updates,
            sequence_comments
          )
            source_updates = updates.select do |update|
              source_node = T.must(update.declaration.source_node)
              node_within?(source_node, child)
            end
            source_updates = source_updates.uniq { |update| T.must(update.declaration.source_node) }
            comment_updates = grouped_updates.select do |update|
              update.declaration.sequence_item_index == index
            end
            child_source = workflow_file.node_source(child).strip
            child_source = replace_declarations_in_node_source(child, child_source, source_updates)

            sequence_comments.render_item(
              index: index,
              item_count: item_count,
              source: child_source,
              updates: comment_updates
            )
          end

          sig do
            params(
              sequence: Psych::Nodes::Sequence,
              lines: T::Array[String],
              closing_indent: String
            ).returns(String)
          end
          def flow_sequence_replacement(sequence, lines, closing_indent)
            source = workflow_file.node_source(sequence)
            opening_bracket = T.must(source.b.index("["))
            closing_bracket = T.must(source.b.rindex("]"))
            prefix = source.byteslice(0...opening_bracket) || ""
            suffix = source.byteslice((closing_bracket + 1)..) || ""
            expanded = [
              "[",
              lines.join(workflow_file.newline),
              "#{closing_indent}]"
            ].join(workflow_file.newline)
            prefix + expanded + suffix
          end

          sig do
            params(
              container_node: Psych::Nodes::Node,
              container_source: String,
              source_updates: T::Array[SourceUpdate]
            ).returns(String)
          end
          def replace_declarations_in_node_source(container_node, container_source, source_updates)
            container_start = node_start_offset(container_node)
            changes = unique_edits(source_updates.map { |update| source_value_change(update) })
            changes.sort_by(&:start_offset).reverse_each.reduce(container_source) do |source, change|
              replace_bytes(
                source,
                change.start_offset - container_start,
                change.end_offset - container_start,
                change.replacement
              )
            end
          end

          sig { params(update: SourceUpdate).returns(ContentEdit) }
          def source_value_edit(update)
            source_value_change(update)
          end

          sig { params(update: SourceUpdate).returns(ContentEdit) }
          def source_value_change(update)
            source_node = T.must(update.declaration.source_node)
            node_start = node_start_offset(source_node)
            source = workflow_file.node_source(source_node)
            declaration = update.old_declaration.strip
            relative_start = source.b.index(declaration.b)
            if relative_start
              return ContentEdit.new(
                start_offset: node_start + relative_start,
                end_offset: node_start + relative_start + declaration.bytesize,
                replacement: update.new_declaration.strip
              )
            end

            quoted_scalar_change(source_node, source, node_start, update)
          end

          sig do
            params(
              source_node: Psych::Nodes::Node,
              source: String,
              node_start: Integer,
              update: SourceUpdate
            ).returns(ContentEdit)
          end
          def quoted_scalar_change(source_node, source, node_start, update)
            raise "Expected workflow source to include #{update.old_declaration}" unless
              source_node.is_a?(Psych::Nodes::Scalar)

            style = workflow_file.scalar_node_style(source_node)
            quote = case style
                    when Psych::Nodes::Scalar::SINGLE_QUOTED then "'"
                    when Psych::Nodes::Scalar::DOUBLE_QUOTED then '"'
                    end
            raise "Expected workflow source to include #{update.old_declaration}" unless quote

            value_start = T.must(source.b.index(quote.b))
            value_end = T.must(source.b.rindex(quote.b))
            replacement = escaped_quoted_value(update.new_declaration.strip, quote)
            ContentEdit.new(
              start_offset: node_start + value_start + 1,
              end_offset: node_start + value_end,
              replacement: replacement
            )
          end

          sig { params(value: String, quote: String).returns(String) }
          def escaped_quoted_value(value, quote)
            return value.gsub("'", "''") if quote == "'"

            value.gsub("\\", "\\\\").gsub('"', '\\"')
          end

          sig { params(child: Psych::Nodes::Node, parent: Psych::Nodes::Node).returns(T::Boolean) }
          def node_within?(child, parent)
            node_start_offset(child) >= node_start_offset(parent) &&
              node_end_offset(child) <= node_end_offset(parent)
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

          sig { params(edits: T::Array[ContentEdit]).returns(String) }
          def apply_content_edits(edits)
            ordered_edits = unique_edits(edits).sort_by(&:start_offset)
            (0...(ordered_edits.length - 1)).each do |index|
              left = T.must(ordered_edits[index])
              right = T.must(ordered_edits[index + 1])
              raise "Overlapping workflow edits" if left.end_offset > right.start_offset
            end

            ordered_edits.reverse_each.reduce(workflow_file.content) do |content, edit|
              replace_bytes(content, edit.start_offset, edit.end_offset, edit.replacement)
            end
          end

          sig { params(edits: T::Array[ContentEdit]).returns(T::Array[ContentEdit]) }
          def unique_edits(edits)
            edits_by_range = T.let({}, T::Hash[[Integer, Integer], ContentEdit])
            edits.each do |edit|
              key = [edit.start_offset, edit.end_offset]
              existing = edits_by_range[key]
              if existing && existing.replacement != edit.replacement
                raise "Conflicting workflow edits at #{edit.start_offset}"
              end

              edits_by_range[key] = edit
            end
            edits_by_range.values
          end

          sig do
            params(
              content: String,
              start_offset: Integer,
              end_offset: Integer,
              replacement: String
            ).returns(String)
          end
          def replace_bytes(content, start_offset, end_offset, replacement)
            prefix = content.byteslice(0...start_offset) || ""
            suffix = content.byteslice(end_offset..) || ""
            prefix + replacement + suffix
          end
        end
      end
    end
  end
end
