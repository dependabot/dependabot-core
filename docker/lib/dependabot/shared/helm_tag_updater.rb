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
        YAML.parse_stream(content).children.each do |document|
          nodes.concat(document_tag_nodes(document, old_images, document_aliases(document)))
        end
        nodes
      end

      sig do
        params(document: Psych::Nodes::Document).returns(T::Hash[Psych::Nodes::Alias, Psych::Nodes::Node])
      end
      def document_aliases(document)
        anchors = T.let({}, T::Hash[String, Psych::Nodes::Node])
        aliases = T.let({}, T::Hash[Psych::Nodes::Alias, Psych::Nodes::Node])
        document.sort_by { |node| [node.start_line, node.start_column] }.each do |node|
          if node.is_a?(Psych::Nodes::Alias)
            target = anchors[node.anchor]
            aliases[node] = target if target
          elsif node.respond_to?(:anchor) && node.anchor
            anchors[node.anchor] = node
          end
        end
        aliases
      end

      sig do
        params(
          document: Psych::Nodes::Document,
          old_images: T::Array[String],
          aliases: T::Hash[Psych::Nodes::Alias, Psych::Nodes::Node]
        ).returns(T::Array[Psych::Nodes::Scalar])
      end
      def document_tag_nodes(document, old_images, aliases)
        nodes = T.let([], T::Array[Psych::Nodes::Scalar])
        document.each do |node|
          next unless node.is_a?(Psych::Nodes::Mapping)

          node.children.each_slice(2) do |key, value|
            next unless key.is_a?(Psych::Nodes::Scalar) && key.value == "image"
            next unless value.is_a?(Psych::Nodes::Mapping)

            tag = matching_image_tag(value, old_images, aliases)
            nodes << tag if tag
          end
        end
        nodes
      end

      sig do
        params(
          node: Psych::Nodes::Mapping,
          old_images: T::Array[String],
          aliases: T::Hash[Psych::Nodes::Alias, Psych::Nodes::Node]
        ).returns(T.nilable(Psych::Nodes::Scalar))
      end
      def matching_image_tag(node, old_images, aliases)
        fields = scalar_fields(node)
        repository = mapping_field(node, "repository", aliases)
        tag = fields["tag"] || fields["version"]
        return unless repository.is_a?(Psych::Nodes::Scalar) && tag
        # Updating an anchor would also change any unrelated images that alias it.
        return if tag.anchor

        registry = mapping_field(node, "registry", aliases)
        image = "#{"#{registry.value}/" if registry.is_a?(Psych::Nodes::Scalar)}#{repository.value}:#{tag.value}"
        tag if old_images.include?(image.delete_prefix("docker.io/"))
      end

      sig do
        params(
          node: Psych::Nodes::Node,
          key: String,
          aliases: T::Hash[Psych::Nodes::Alias, Psych::Nodes::Node],
          visited: T::Array[Psych::Nodes::Node]
        ).returns(T.nilable(Psych::Nodes::Node))
      end
      def mapping_field(node, key, aliases, visited = [])
        node = aliases[node] if node.is_a?(Psych::Nodes::Alias)
        return unless node.is_a?(Psych::Nodes::Mapping)
        return if visited.include?(node)

        fields = node.children.each_slice(2).with_object({}) do |(field, value), mapping|
          mapping[field.value] = value if field.is_a?(Psych::Nodes::Scalar)
        end
        if fields.key?(key)
          value = fields[key]
          return value.is_a?(Psych::Nodes::Alias) ? aliases[value] : value
        end

        merge = fields["<<"]
        merges = merge.is_a?(Psych::Nodes::Sequence) ? merge.children : [merge].compact
        merges.lazy.filter_map { |parent| mapping_field(parent, key, aliases, visited + [node]) }.first
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
