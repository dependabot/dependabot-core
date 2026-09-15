# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "yaml"

module Dependabot
  module Shared
    class HelmTagUpdater
      extend T::Sig

      sig { params(content: String, old_images: T::Array[String], new_tag: String).returns(String) }
      def updated_content(content:, old_images:, new_tag:)
        nodes = image_tag_nodes(content, old_images)
        line_offsets = T.let([0], T::Array[Integer])
        content.each_line { |line| line_offsets << (T.must(line_offsets.last) + line.length) }
        updated_content = content.dup

        # Work backwards so earlier node locations are unaffected by replacements.
        nodes.sort_by { |node| [node.start_line, node.start_column] }.reverse_each do |node|
          start_offset = line_offsets.fetch(node.start_line) + node.start_column
          end_offset = line_offsets.fetch(node.end_line) + node.end_column
          range = start_offset...end_offset
          updated_content[range] = T.must(updated_content[range]).sub(node.value) { new_tag }
        end

        updated_content
      end

      private

      sig { params(content: String, old_images: T::Array[String]).returns(T::Array[Psych::Nodes::Scalar]) }
      def image_tag_nodes(content, old_images)
        nodes = T.let([], T::Array[Psych::Nodes::Scalar])
        YAML.parse_stream(content).each do |node|
          next unless node.is_a?(Psych::Nodes::Mapping)

          node.children.each_slice(2) do |key, value|
            next unless key.is_a?(Psych::Nodes::Scalar) && key.value == "image"
            next unless value.is_a?(Psych::Nodes::Mapping)

            tag = matching_image_tag(value, old_images)
            nodes << tag if tag
          end
        end
        nodes
      end

      sig do
        params(node: Psych::Nodes::Mapping, old_images: T::Array[String]).returns(T.nilable(Psych::Nodes::Scalar))
      end
      def matching_image_tag(node, old_images)
        fields = scalar_fields(node)
        repository = fields["repository"]&.value
        tag = fields["tag"] || fields["version"]
        return unless repository && tag

        registry = fields["registry"]&.value
        image = "#{"#{registry}/" if registry}#{repository}:#{tag.value}"
        tag if old_images.include?(image.delete_prefix("docker.io/"))
      end

      sig { params(node: Psych::Nodes::Mapping).returns(T::Hash[String, Psych::Nodes::Scalar]) }
      def scalar_fields(node)
        node.children.each_slice(2).with_object({}) do |(key, value), fields|
          next unless key.is_a?(Psych::Nodes::Scalar) && value.is_a?(Psych::Nodes::Scalar)

          fields[key.value] = value
        end
      end
    end
  end
end
