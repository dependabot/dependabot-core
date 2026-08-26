# typed: strict
# frozen_string_literal: true

require "date"
require "sorbet-runtime"
require "yaml"

require "dependabot/github_actions/constants"

module Dependabot
  module GithubActions
    class WorkflowFile
      extend T::Sig

      Path = T.type_alias { T::Array[T.any(String, Integer)] }
      Metadata = T.type_alias { T::Hash[Symbol, Object] }

      require_relative "workflow_file/node_context"
      require_relative "workflow_file/uses_declaration"
      require_relative "workflow_file/uses_collector"
      require_relative "workflow_file/metadata_builder"

      sig { params(content: String).void }
      def initialize(content)
        @content = content
        @data = T.let(
          T.cast(
            YAML.safe_load(content, aliases: true, permitted_classes: [Date, Time, Symbol]),
            T.nilable(Object)
          ),
          T.nilable(Object)
        )
        @contexts = T.let({}, T::Hash[Path, NodeContext])
        @anchors = T.let({}, T::Hash[String, Psych::Nodes::Node])
        @alias_targets = T.let({}, T::Hash[Path, Psych::Nodes::Node])
        @sequences = T.let([], T::Array[Psych::Nodes::Sequence])
        @steps_key_nodes = T.let({}, T::Hash[Psych::Nodes::Sequence, Psych::Nodes::Scalar])
        @lines = T.let(content.lines, T::Array[String])
        @line_offsets = T.let(line_offsets(content), T::Array[Integer])

        index_stream(YAML.parse_stream(content))
        @uses_declarations = T.let(build_uses_declarations, T::Array[UsesDeclaration])
      end

      sig { returns(T.nilable(Object)) }
      attr_reader :data

      sig { returns(T::Array[UsesDeclaration]) }
      attr_reader :uses_declarations

      sig { returns(String) }
      attr_reader :content

      sig { returns(T::Array[Psych::Nodes::Sequence]) }
      attr_reader :sequences

      sig { returns(T::Array[Psych::Nodes::Sequence]) }
      def steps_sequences = @steps_key_nodes.keys

      sig { params(sequence: Psych::Nodes::Sequence).returns(T.nilable(Psych::Nodes::Scalar)) }
      def steps_key_node_for(sequence) = @steps_key_nodes[sequence]

      sig { params(path: Path).returns(T.nilable(UsesDeclaration)) }
      def declaration_at(path) = uses_declarations.find { |declaration| declaration.path == path }

      sig { params(sequence: Psych::Nodes::Sequence).returns(T::Array[UsesDeclaration]) }
      def declarations_in_sequence(sequence) = uses_declarations.select { |item| item.steps_sequence.equal?(sequence) }

      sig { params(declaration: UsesDeclaration).returns(T::Boolean) }
      def source_metadata_required?(declaration)
        return true if declaration.value_node.is_a?(Psych::Nodes::Alias)

        source_node = declaration.source_node
        if source_node.is_a?(Psych::Nodes::Scalar)
          return true if block_scalar_style?(scalar_node_style(source_node))
          return true unless node_source(source_node).include?(declaration.value.strip)
        end

        sequence = declaration.steps_sequence
        return true if sequence && sequence_node_style(sequence) == Psych::Nodes::Sequence::FLOW

        MetadataBuilder.new(self).comment_line_collision?(declaration)
      end

      sig { params(declaration: UsesDeclaration).returns(Metadata) }
      def source_metadata(declaration) = MetadataBuilder.new(self).build(declaration)

      sig { params(node: Psych::Nodes::Node).returns(String) }
      def node_source(node)
        start_offset = offset(node_start_line(node), node_start_column(node))
        end_offset = offset(node_end_line(node), node_end_column(node))
        T.must(content.byteslice(start_offset...end_offset))
      end

      sig { params(node: Psych::Nodes::Node).returns(Integer) }
      def node_start_line(node)
        T.cast(node.start_line, Integer)
      end

      sig { params(node: Psych::Nodes::Node).returns(Integer) }
      def node_start_column(node)
        T.cast(node.start_column, Integer)
      end

      sig { params(node: Psych::Nodes::Node).returns(Integer) }
      def node_end_line(node)
        T.cast(node.end_line, Integer)
      end

      sig { params(node: Psych::Nodes::Node).returns(Integer) }
      def node_end_column(node)
        T.cast(node.end_column, Integer)
      end

      sig { params(node: Psych::Nodes::Sequence).returns(Integer) }
      def sequence_node_style(node)
        T.cast(node.style, Integer)
      end

      sig { params(node: Psych::Nodes::Mapping).returns(Integer) }
      def mapping_node_style(node)
        T.cast(node.style, Integer)
      end

      sig { params(node: Psych::Nodes::Scalar).returns(Integer) }
      def scalar_node_style(node)
        T.cast(node.style, Integer)
      end

      sig { params(node: Psych::Nodes::Node).returns(T::Array[Psych::Nodes::Node]) }
      def node_children(node)
        children = node.children
        return [] unless children.is_a?(Array)

        children
      end

      sig { params(line: Integer, column: Integer).returns(Integer) }
      def offset(line, column)
        line_start = T.must(@line_offsets[line])
        line_content = @lines[line] || ""
        prefix = line_content[0, column] || ""
        line_start + prefix.bytesize
      end

      sig { params(line: Integer, column: Integer).returns(Integer) }
      def byte_column(line, column)
        offset(line, column) - T.must(@line_offsets[line])
      end

      sig { params(line: Integer).returns(String) }
      def line_body(line)
        start_offset = T.must(@line_offsets[line])
        end_offset = @line_offsets[line + 1] || content.bytesize
        value = T.must(content.byteslice(start_offset...end_offset))
        value = value.delete_suffix("\n")
        value.delete_suffix("\r")
      end

      sig { params(line: Integer).returns(Integer) }
      def line_end_offset(line)
        T.must(@line_offsets[line]) + line_body(line).bytesize
      end

      sig { returns(String) }
      def newline
        content.include?("\r\n") ? "\r\n" : "\n"
      end

      private

      sig { params(stream: Psych::Nodes::Stream).void }
      def index_stream(stream)
        document = node_children(stream).first
        return unless document.is_a?(Psych::Nodes::Document)

        root = node_children(document).first
        return unless root

        index_node(
          root,
          [],
          mapping_node: nil,
          key_node: nil,
          steps_sequence: nil,
          steps_key_node: nil,
          sequence_item: nil,
          sequence_item_index: nil
        )
      end

      sig do
        params(
          node: Psych::Nodes::Node,
          path: Path,
          mapping_node: T.nilable(Psych::Nodes::Mapping),
          key_node: T.nilable(Psych::Nodes::Scalar),
          steps_sequence: T.nilable(Psych::Nodes::Sequence),
          steps_key_node: T.nilable(Psych::Nodes::Scalar),
          sequence_item: T.nilable(Psych::Nodes::Node),
          sequence_item_index: T.nilable(Integer)
        ).void
      end
      def index_node(
        node,
        path,
        mapping_node:,
        key_node:,
        steps_sequence:,
        steps_key_node:,
        sequence_item:,
        sequence_item_index:
      )
        record_node(
          node,
          path,
          mapping_node: mapping_node,
          key_node: key_node,
          steps_sequence: steps_sequence,
          steps_key_node: steps_key_node,
          sequence_item: sequence_item,
          sequence_item_index: sequence_item_index
        )

        index_node_children(
          node,
          path,
          steps_sequence: steps_sequence,
          steps_key_node: steps_key_node,
          sequence_item: sequence_item,
          sequence_item_index: sequence_item_index
        )
      end

      sig do
        params(
          node: Psych::Nodes::Node,
          path: Path,
          mapping_node: T.nilable(Psych::Nodes::Mapping),
          key_node: T.nilable(Psych::Nodes::Scalar),
          steps_sequence: T.nilable(Psych::Nodes::Sequence),
          steps_key_node: T.nilable(Psych::Nodes::Scalar),
          sequence_item: T.nilable(Psych::Nodes::Node),
          sequence_item_index: T.nilable(Integer)
        ).void
      end
      def record_node(
        node,
        path,
        mapping_node:,
        key_node:,
        steps_sequence:,
        steps_key_node:,
        sequence_item:,
        sequence_item_index:
      )
        @contexts[path] = NodeContext.new(
          node: node,
          mapping_node: mapping_node,
          key_node: key_node,
          steps_sequence: steps_sequence,
          steps_key_node: steps_key_node,
          sequence_item: sequence_item,
          sequence_item_index: sequence_item_index
        )
        if node.is_a?(Psych::Nodes::Alias)
          target = @anchors[node.anchor]
          @alias_targets[path] = target if target
        end

        anchor = node_anchor(node)
        @anchors[anchor] = node if anchor
        @sequences << node if node.is_a?(Psych::Nodes::Sequence)
      end

      sig do
        params(
          node: Psych::Nodes::Node,
          path: Path,
          steps_sequence: T.nilable(Psych::Nodes::Sequence),
          steps_key_node: T.nilable(Psych::Nodes::Scalar),
          sequence_item: T.nilable(Psych::Nodes::Node),
          sequence_item_index: T.nilable(Integer)
        ).void
      end
      def index_node_children(
        node,
        path,
        steps_sequence:,
        steps_key_node:,
        sequence_item:,
        sequence_item_index:
      )
        case node
        when Psych::Nodes::Mapping
          index_mapping(
            node,
            path,
            steps_sequence: steps_sequence,
            steps_key_node: steps_key_node,
            sequence_item: sequence_item,
            sequence_item_index: sequence_item_index
          )
        when Psych::Nodes::Sequence
          node_children(node).each_with_index do |child, index|
            index_node(
              child,
              path + [index],
              mapping_node: nil,
              key_node: nil,
              steps_sequence: steps_sequence,
              steps_key_node: steps_key_node,
              sequence_item: child,
              sequence_item_index: index
            )
          end
        end
      end

      sig do
        params(
          node: Psych::Nodes::Mapping,
          path: Path,
          steps_sequence: T.nilable(Psych::Nodes::Sequence),
          steps_key_node: T.nilable(Psych::Nodes::Scalar),
          sequence_item: T.nilable(Psych::Nodes::Node),
          sequence_item_index: T.nilable(Integer)
        ).void
      end
      def index_mapping(
        node,
        path,
        steps_sequence:,
        steps_key_node:,
        sequence_item:,
        sequence_item_index:
      )
        node_children(node).each_slice(2) do |raw_key_node, value_node|
          next unless raw_key_node.is_a?(Psych::Nodes::Scalar) && value_node

          child_steps_sequence = steps_sequence
          child_steps_key_node = steps_key_node
          if raw_key_node.value == STEPS_KEY && value_node.is_a?(Psych::Nodes::Sequence)
            child_steps_sequence = value_node
            child_steps_key_node = raw_key_node
            @steps_key_nodes[value_node] = raw_key_node
          end

          index_node(
            value_node,
            path + [raw_key_node.value],
            mapping_node: node,
            key_node: raw_key_node,
            steps_sequence: child_steps_sequence,
            steps_key_node: child_steps_key_node,
            sequence_item: sequence_item,
            sequence_item_index: sequence_item_index
          )
        end
      end

      sig { returns(T::Array[UsesDeclaration]) }
      def build_uses_declarations
        UsesCollector.new(data).uses.map do |resolved_use|
          build_declaration(resolved_use.value, resolved_use.path)
        end
      end

      sig { params(value: String, path: Path).returns(UsesDeclaration) }
      def build_declaration(value, path)
        context = @contexts[path]
        value_node = context&.node
        source_node =
          if value_node.is_a?(Psych::Nodes::Alias)
            @alias_targets[path]
          else
            value_node
          end

        UsesDeclaration.new(
          value: value,
          path: path,
          value_node: value_node,
          source_node: source_node,
          mapping_node: context&.mapping_node,
          steps_sequence: context&.steps_sequence,
          steps_key_node: context&.steps_key_node,
          sequence_item: context&.sequence_item,
          sequence_item_index: context&.sequence_item_index
        )
      end

      sig { params(style: Integer).returns(T::Boolean) }
      def block_scalar_style?(style)
        [Psych::Nodes::Scalar::LITERAL, Psych::Nodes::Scalar::FOLDED].include?(style)
      end

      sig { params(node: Psych::Nodes::Node).returns(T.nilable(String)) }
      def node_anchor(node)
        case node
        when Psych::Nodes::Scalar, Psych::Nodes::Mapping, Psych::Nodes::Sequence
          node.anchor
        end
      end

      sig { params(value: String).returns(T::Array[Integer]) }
      def line_offsets(value)
        offsets = [0]
        value.each_line { |line| offsets << (offsets.last + line.bytesize) }
        offsets
      end
    end
  end
end
