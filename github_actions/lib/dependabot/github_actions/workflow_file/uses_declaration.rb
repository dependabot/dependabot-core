# typed: strict
# frozen_string_literal: true

require "dependabot/github_actions/workflow_file"

module Dependabot
  module GithubActions
    class WorkflowFile
      class UsesDeclaration
        extend T::Sig

        sig do
          params(
            value: String,
            path: Path,
            value_node: T.nilable(Psych::Nodes::Node),
            source_node: T.nilable(Psych::Nodes::Node),
            mapping_node: T.nilable(Psych::Nodes::Mapping),
            steps_sequence: T.nilable(Psych::Nodes::Sequence),
            steps_key_node: T.nilable(Psych::Nodes::Scalar),
            sequence_item: T.nilable(Psych::Nodes::Node),
            sequence_item_index: T.nilable(Integer)
          ).void
        end
        def initialize(
          value:,
          path:,
          value_node:,
          source_node:,
          mapping_node:,
          steps_sequence:,
          steps_key_node:,
          sequence_item:,
          sequence_item_index:
        )
          @value = value
          @path = path
          @value_node = value_node
          @source_node = source_node
          @mapping_node = mapping_node
          @steps_sequence = steps_sequence
          @steps_key_node = steps_key_node
          @sequence_item = sequence_item
          @sequence_item_index = sequence_item_index
        end

        sig { returns(String) }
        attr_reader :value

        sig { returns(Path) }
        attr_reader :path

        sig { returns(T.nilable(Psych::Nodes::Node)) }
        attr_reader :value_node

        sig { returns(T.nilable(Psych::Nodes::Node)) }
        attr_reader :source_node

        sig { returns(T.nilable(Psych::Nodes::Mapping)) }
        attr_reader :mapping_node

        sig { returns(T.nilable(Psych::Nodes::Sequence)) }
        attr_reader :steps_sequence

        sig { returns(T.nilable(Psych::Nodes::Scalar)) }
        attr_reader :steps_key_node

        sig { returns(T.nilable(Psych::Nodes::Node)) }
        attr_reader :sequence_item

        sig { returns(T.nilable(Integer)) }
        attr_reader :sequence_item_index
      end
    end
  end
end
