# typed: strict
# frozen_string_literal: true

require "dependabot/github_actions/workflow_file"

module Dependabot
  module GithubActions
    class WorkflowFile
      class MetadataBuilder
        extend T::Sig

        sig { params(workflow_file: WorkflowFile).void }
        def initialize(workflow_file)
          @workflow_file = workflow_file
        end

        sig { params(declaration: UsesDeclaration).returns(Metadata) }
        def build(declaration)
          metadata = T.let(
            {
              path: declaration.path,
              value: node_metadata(declaration.value_node),
              target: node_metadata(declaration.source_node),
              mapping: node_metadata(declaration.mapping_node)
            },
            Metadata
          )

          sequence = declaration.steps_sequence
          if sequence
            metadata[:sequence] = sequence_metadata(
              sequence,
              declaration.steps_key_node,
              declaration.sequence_item_index
            )
          end

          metadata
        end

        sig { params(declaration: UsesDeclaration).returns(T::Array[UsesDeclaration]) }
        def collision_declarations_for(declaration)
          anchor = comment_anchor(declaration)
          return [] unless anchor

          workflow_file.uses_declarations.select do |item|
            item_anchor = comment_anchor(item)
            item_anchor && item_anchor.first == anchor.first
          end
        end

        sig { params(declaration: UsesDeclaration).returns(T::Boolean) }
        def comment_line_collision?(declaration)
          anchor = comment_anchor(declaration)
          return false unless anchor
          return true if collision_declarations_for(declaration).length > 1

          line = anchor.first
          anchor_offset = workflow_file.offset(anchor.first, anchor.last)
          workflow_file.steps_sequences.any? do |sequence|
            sequence_starts_after_anchor?(sequence, line, anchor_offset) ||
              child_starts_after_anchor?(sequence, line, anchor_offset)
          end
        end

        sig { params(declaration: UsesDeclaration).returns(T::Array[Psych::Nodes::Sequence]) }
        def collision_sequences_for(declaration)
          anchor = comment_anchor(declaration)
          return [] unless anchor

          line = anchor.first
          workflow_file.steps_sequences.select do |sequence|
            line.between?(
              workflow_file.node_start_line(sequence),
              workflow_file.node_end_line(sequence)
            )
          end
        end

        sig { params(declaration: UsesDeclaration).returns(T.nilable([Integer, Integer])) }
        def comment_anchor(declaration)
          source_node = declaration.source_node
          return unless source_node

          if source_node.is_a?(Psych::Nodes::Scalar) && block_scalar?(source_node)
            return [
              workflow_file.node_start_line(source_node),
              workflow_file.node_start_column(source_node)
            ]
          end

          mapping = declaration.mapping_node
          if mapping && workflow_file.mapping_node_style(mapping) == Psych::Nodes::Mapping::FLOW
            return [workflow_file.node_end_line(mapping), workflow_file.node_end_column(mapping)]
          end

          value_node = declaration.value_node
          return unless value_node

          [workflow_file.node_end_line(value_node), workflow_file.node_end_column(value_node)]
        end

        private

        sig { returns(WorkflowFile) }
        attr_reader :workflow_file

        sig do
          params(
            sequence: Psych::Nodes::Sequence,
            line: Integer,
            anchor_offset: Integer
          ).returns(T::Boolean)
        end
        def sequence_starts_after_anchor?(sequence, line, anchor_offset)
          workflow_file.node_start_line(sequence) == line && node_start_offset(sequence) > anchor_offset
        end

        sig do
          params(
            sequence: Psych::Nodes::Sequence,
            line: Integer,
            anchor_offset: Integer
          ).returns(T::Boolean)
        end
        def child_starts_after_anchor?(sequence, line, anchor_offset)
          workflow_file.node_children(sequence).any? do |child|
            workflow_file.node_start_line(child) == line && node_start_offset(child) > anchor_offset
          end
        end

        sig { params(node: Psych::Nodes::Node).returns(Integer) }
        def node_start_offset(node)
          workflow_file.offset(
            workflow_file.node_start_line(node),
            workflow_file.node_start_column(node)
          )
        end

        sig { params(node: Psych::Nodes::Scalar).returns(T::Boolean) }
        def block_scalar?(node)
          style = workflow_file.scalar_node_style(node)
          [Psych::Nodes::Scalar::LITERAL, Psych::Nodes::Scalar::FOLDED].include?(style)
        end

        sig { params(node: T.nilable(Psych::Nodes::Node)).returns(Metadata) }
        def node_metadata(node)
          return {} unless node

          metadata = T.let(
            {
              kind: node_kind(node),
              start_line: workflow_file.node_start_line(node),
              start_column: workflow_file.node_start_column(node),
              end_line: workflow_file.node_end_line(node),
              end_column: workflow_file.node_end_column(node)
            },
            Metadata
          )

          if node.is_a?(Psych::Nodes::Scalar)
            metadata[:style] = scalar_style(workflow_file.scalar_node_style(node))
            metadata[:anchor] = node.anchor if node.anchor
          elsif node.is_a?(Psych::Nodes::Alias)
            metadata[:anchor] = node.anchor
          end

          metadata
        end

        sig do
          params(
            sequence: Psych::Nodes::Sequence,
            key_node: T.nilable(Psych::Nodes::Scalar),
            item_index: T.nilable(Integer)
          ).returns(Metadata)
        end
        def sequence_metadata(sequence, key_node, item_index)
          metadata = node_metadata(sequence)
          metadata[:style] =
            workflow_file.sequence_node_style(sequence) == Psych::Nodes::Sequence::FLOW ? "flow" : "block"
          metadata[:item_index] = item_index if item_index
          metadata[:item_count] = workflow_file.node_children(sequence).length
          metadata[:key_start_column] = workflow_file.node_start_column(key_node) if key_node
          metadata
        end

        sig { params(node: Psych::Nodes::Node).returns(String) }
        def node_kind(node)
          case node
          when Psych::Nodes::Alias then "alias"
          when Psych::Nodes::Scalar then "scalar"
          when Psych::Nodes::Mapping then "mapping"
          when Psych::Nodes::Sequence then "sequence"
          else "node"
          end
        end

        sig { params(style: Integer).returns(String) }
        def scalar_style(style)
          case style
          when Psych::Nodes::Scalar::SINGLE_QUOTED then "single_quoted"
          when Psych::Nodes::Scalar::DOUBLE_QUOTED then "double_quoted"
          when Psych::Nodes::Scalar::LITERAL then "literal"
          when Psych::Nodes::Scalar::FOLDED then "folded"
          else "plain"
          end
        end
      end
    end
  end
end
