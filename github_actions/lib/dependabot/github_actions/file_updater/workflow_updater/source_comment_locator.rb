# typed: strong
# frozen_string_literal: true

require "dependabot/github_actions/file_updater/workflow_updater"

module Dependabot
  module GithubActions
    class FileUpdater < Dependabot::FileUpdaters::Base
      class WorkflowUpdater
        class SourceCommentLocator
          extend T::Sig

          class LocatedComment < T::Struct
            const :comment, String
            const :start_offset, Integer
            const :end_offset, Integer
            const :syntax_adjacent, T::Boolean
          end

          sig do
            params(
              workflow_file: WorkflowFile,
              comment_finder: YamlCommentFinder,
              metadata_builder: WorkflowFile::MetadataBuilder
            ).void
          end
          def initialize(workflow_file:, comment_finder:, metadata_builder:)
            @workflow_file = workflow_file
            @comment_finder = comment_finder
            @metadata_builder = metadata_builder
          end

          sig { params(declaration: WorkflowFile::UsesDeclaration).returns(T.nilable(LocatedComment)) }
          def for_declaration(declaration)
            anchor = metadata_builder.comment_anchor(declaration)
            return unless anchor

            locate(
              line: anchor.first,
              column: anchor.last,
              owner_sequence: declaration.steps_sequence,
              block_scalar: block_scalar?(declaration.source_node)
            )
          end

          sig { params(sequence: Psych::Nodes::Sequence).returns(T.nilable(LocatedComment)) }
          def for_sequence(sequence)
            locate(
              line: workflow_file.node_end_line(sequence),
              column: workflow_file.node_end_column(sequence),
              owner_sequence: sequence,
              block_scalar: false
            )
          end

          sig { params(source: String).returns(T.nilable(String)) }
          def find_line(source)
            comment_finder.find_line(source)
          end

          private

          sig { returns(WorkflowFile) }
          attr_reader :workflow_file

          sig { returns(YamlCommentFinder) }
          attr_reader :comment_finder

          sig { returns(WorkflowFile::MetadataBuilder) }
          attr_reader :metadata_builder

          sig do
            params(
              line: Integer,
              column: Integer,
              owner_sequence: T.nilable(Psych::Nodes::Sequence),
              block_scalar: T::Boolean
            ).returns(T.nilable(LocatedComment))
          end
          def locate(line:, column:, owner_sequence:, block_scalar:)
            suffix = workflow_file.line_body(line).byteslice(workflow_file.byte_column(line, column)..) || ""
            comment = comment_finder.find(suffix)
            return unless comment

            relative_start = T.must(suffix.b.index(comment.b))
            start_offset = workflow_file.offset(line, column) + relative_start
            return if inside_other_sequence?(start_offset, owner_sequence)

            prefix = suffix.byteslice(0...relative_start) || ""
            LocatedComment.new(
              comment: comment,
              start_offset: start_offset,
              end_offset: start_offset + comment.bytesize,
              syntax_adjacent: adjacent_prefix?(prefix, block_scalar)
            )
          end

          sig do
            params(
              offset: Integer,
              owner_sequence: T.nilable(Psych::Nodes::Sequence)
            ).returns(T::Boolean)
          end
          def inside_other_sequence?(offset, owner_sequence)
            workflow_file.sequences.any? do |sequence|
              next false if owner_sequence.equal?(sequence)

              node_start_offset(sequence) <= offset && offset < node_end_offset(sequence)
            end
          end

          sig { params(prefix: String, block_scalar: T::Boolean).returns(T::Boolean) }
          def adjacent_prefix?(prefix, block_scalar)
            return true if prefix.match?(/\A[ \t,\]\}]*\z/)
            return false unless block_scalar

            prefix.match?(/\A[>|0-9+-]+[ \t]*\z/)
          end

          sig { params(node: T.nilable(Psych::Nodes::Node)).returns(T::Boolean) }
          def block_scalar?(node)
            return false unless node.is_a?(Psych::Nodes::Scalar)

            style = workflow_file.scalar_node_style(node)
            [Psych::Nodes::Scalar::LITERAL, Psych::Nodes::Scalar::FOLDED].include?(style)
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
