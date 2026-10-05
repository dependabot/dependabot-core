# typed: strict
# frozen_string_literal: true

require "json"
require "sorbet-runtime"

require "dependabot/errors"
require "dependabot/file_updaters/base"
require "dependabot/kotlin_toolchain/yaml_parser"

module Dependabot
  module KotlinToolchain
    class FileUpdater < Dependabot::FileUpdaters::Base
      class YamlEditor
        extend T::Sig

        PathPart = T.type_alias { T.any(String, Integer) }

        MERGE_KEY = "<<"
        NODE_PROPERTIES = /\A(?:(?:&\S+|!\S*)\s+)+/

        sig { params(content: String, filename: String).void }
        def initialize(content:, filename:)
          @content = content
          @filename = filename
          @anchors = T.let({}, T::Hash[String, Psych::Nodes::Node])
        end

        sig do
          params(
            path: T::Array[PathPart],
            value: String,
            key: T::Boolean
          ).returns(String)
        end
        def replace(path:, value:, key: false)
          node = node_at(path, key: key)
          unless node.is_a?(Psych::Nodes::Scalar)
            raise Dependabot::DependencyFileNotResolvable,
                  "Unable to locate #{path.join('.')} in #{filename}"
          end
          return content if node.value == value

          if node.start_line != node.end_line
            raise Dependabot::DependencyFileNotResolvable,
                  "Multiline dependency versions are not supported in #{filename}"
          end

          lines = content.lines
          line = T.must(lines[node.start_line])
          original = T.must(line[node.start_column...node.end_column])
          properties = node.anchor || node.tag ? original[NODE_PROPERTIES].to_s : ""
          line[node.start_column...node.end_column] = properties + render(value, style: node.style)
          lines[node.start_line] = line
          lines.join
        end

        private

        sig { returns(String) }
        attr_reader :content

        sig { returns(String) }
        attr_reader :filename

        sig { returns(T::Hash[String, Psych::Nodes::Node]) }
        attr_reader :anchors

        sig { params(path: T::Array[PathPart], key: T::Boolean).returns(T.nilable(Psych::Nodes::Node)) }
        def node_at(path, key:)
          root = YamlParser.parse(content, filename: filename)&.root
          return unless root

          collect_anchors(root)
          path.each_with_index.reduce(resolve(root)) do |current, (part, index)|
            break unless current

            last = index == path.length - 1
            child = child_node(current, part, key: key && last)
            break unless child

            key && last ? child : resolve(child)
          end
        end

        sig { params(node: Psych::Nodes::Node).void }
        def collect_anchors(node)
          case node
          when Psych::Nodes::Scalar, Psych::Nodes::Mapping, Psych::Nodes::Sequence
            anchor = node.anchor
            anchors[anchor] = node if anchor
          end
          node.children&.each { |child| collect_anchors(child) }
        end

        sig { params(node: Psych::Nodes::Node).returns(T.nilable(Psych::Nodes::Node)) }
        def resolve(node)
          return node unless node.is_a?(Psych::Nodes::Alias)

          anchors[node.anchor]
        end

        sig do
          params(
            node: Psych::Nodes::Node,
            part: PathPart,
            key: T::Boolean
          ).returns(T.nilable(Psych::Nodes::Node))
        end
        def child_node(node, part, key:)
          case node
          when Psych::Nodes::Mapping
            mapping_child(node, part, key: key)
          when Psych::Nodes::Sequence
            part.is_a?(Integer) ? node.children[part] : nil
          end
        end

        sig do
          params(
            node: Psych::Nodes::Mapping,
            part: PathPart,
            key: T::Boolean
          ).returns(T.nilable(Psych::Nodes::Node))
        end
        def mapping_child(node, part, key:)
          return unless part.is_a?(String)

          pairs = node.children.each_slice(2).to_a
          pair = pairs.find do |key_node, _value_node|
            key_node.is_a?(Psych::Nodes::Scalar) && key_node.value == part
          end
          return key ? pair.first : pair.last if pair

          merged_child(pairs, part, key: key)
        end

        sig do
          params(
            pairs: T::Array[T::Array[Psych::Nodes::Node]],
            part: String,
            key: T::Boolean
          ).returns(T.nilable(Psych::Nodes::Node))
        end
        def merged_child(pairs, part, key:)
          pairs.each do |key_node, value_node|
            next unless key_node.is_a?(Psych::Nodes::Scalar) && key_node.value == MERGE_KEY

            merged_mappings(value_node).each do |mapping|
              found = mapping_child(mapping, part, key: key)
              return found if found
            end
          end
          nil
        end

        sig { params(node: T.nilable(Psych::Nodes::Node)).returns(T::Array[Psych::Nodes::Mapping]) }
        def merged_mappings(node)
          return [] unless node

          sources = node.is_a?(Psych::Nodes::Sequence) ? node.children : [node]
          sources.filter_map do |source|
            resolved = resolve(source)
            resolved if resolved.is_a?(Psych::Nodes::Mapping)
          end
        end

        sig { params(value: String, style: Integer).returns(String) }
        def render(value, style:)
          case style
          when Psych::Nodes::Scalar::SINGLE_QUOTED
            "'#{value.gsub("'", "''")}'"
          when Psych::Nodes::Scalar::DOUBLE_QUOTED
            JSON.generate(value)
          when Psych::Nodes::Scalar::PLAIN
            value
          else
            raise Dependabot::DependencyFileNotResolvable,
                  "Unsupported YAML scalar style in #{filename}"
          end
        end
      end
    end
  end
end
