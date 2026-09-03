# typed: strict
# frozen_string_literal: true

require "dependabot/shared/shared_file_updater"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "yaml"

module Dependabot
  module Helm
    class FileUpdater < Dependabot::Shared::SharedFileUpdater
      class ImageUpdater
        extend T::Sig
        extend T::Helpers

        sig { params(dependency: Dependency, dependency_files: T::Array[Dependabot::DependencyFile]).void }
        def initialize(dependency:, dependency_files:)
          @dependency_files = dependency_files
          @dependency = dependency
        end

        sig { params(file_name: String).returns(T.nilable(String)) }
        def updated_values_yaml_content(file_name)
          value_file = dependency_files.find { |f| f.name.match?(file_name) }
          raise "Expected a values.yaml file to exist!" if value_file.nil?

          content = value_file.content
          yaml_stream = YAML.parse_stream(T.must(content))

          update_image_tags_recursive(yaml_stream, T.must(content))
        end

        private

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { params(yaml_stream: Psych::Nodes::Stream, content: String).returns(String) }
        def update_image_tags_recursive(yaml_stream, content)
          # -1 keeps a trailing empty element so join restores a final newline
          updated_content = content.dup.split("\n", -1)

          yaml_stream.children.each do |document|
            document.children.each do |root_node|
              updated_content = find_and_update_images(root_node, updated_content)
            end
          end

          updated_content = updated_content.join("\n")

          raise "Expected content to change!" if content == updated_content

          updated_content
        end

        sig { params(node: Psych::Nodes::Node, content: T::Array[String]).returns(T::Array[String]) }
        def find_and_update_images(node, content)
          if node.is_a?(Psych::Nodes::Mapping)
            content = process_mapping_node(node, content)
          elsif node.is_a?(Psych::Nodes::Sequence)
            content = process_sequence_node(node, content)
          end

          content
        end

        sig { params(node: Psych::Nodes::Node, content: T::Array[String]).returns(T::Array[String]) }
        def process_mapping_node(node, content)
          node.children.each_slice(2) do |key_node, value_node|
            next unless key_node.is_a?(Psych::Nodes::Scalar)

            key = key_node.value
            content = process_image_key(key, value_node, content)

            if value_node.is_a?(Psych::Nodes::Mapping) || value_node.is_a?(Psych::Nodes::Sequence)
              content = find_and_update_images(value_node, content)
            end
          end
          content
        end

        sig { params(node: Psych::Nodes::Node, content: T::Array[String]).returns(T::Array[String]) }
        def process_sequence_node(node, content)
          node.children.reduce(content) do |updated_content, child|
            find_and_update_images(child, updated_content)
          end
        end

        sig { params(key: String, value_node: Psych::Nodes::Node, content: T::Array[String]).returns(T::Array[String]) }
        def process_image_key(key, value_node, content)
          return content unless key == "image"

          if value_node.is_a?(Psych::Nodes::Mapping)
            process_mapping_image(value_node, content)
          elsif value_node.is_a?(Psych::Nodes::Scalar)
            process_scalar_image(value_node, content)
          else
            content
          end
        end

        sig { params(value_node: Psych::Nodes::Mapping, content: T::Array[String]).returns(T::Array[String]) }
        def process_mapping_image(value_node, content)
          dependency_name = dependency.name
          has_dependency = contains_dependency?(value_node, dependency_name)
          return content unless has_dependency

          dependency_version = T.must(dependency.version)
          update_version_tags(value_node, content, dependency_version)
        end

        sig { params(value_node: Psych::Nodes::Scalar, content: T::Array[String]).returns(T::Array[String]) }
        def process_scalar_image(value_node, content)
          dependency_version = T.must(dependency.version)
          update_scalar_image_tag(value_node, content, dependency_version)
        end

        sig { params(node: Psych::Nodes::Node, dependency_name: String).returns(T::Boolean) }
        def contains_dependency?(node, dependency_name)
          node.children.any? do |child|
            child.is_a?(Psych::Nodes::Scalar) && child.value == dependency_name
          end
        end

        sig do
          params(
            value_node: Psych::Nodes::Mapping,
            content: T::Array[String],
            dependency_version: String
          ).returns(T::Array[String])
        end
        def update_version_tags(value_node, content, dependency_version)
          dependency.requirements.each do |req|
            next unless req.metadata_symbol("type") == :docker_image

            tag_value = req.source_string("tag")
            next unless tag_value

            version_scalar = value_node.children.find do |node|
              node.is_a?(Psych::Nodes::Scalar) && node.value == tag_value
            end

            if version_scalar
              line = version_scalar.start_line
              content[line] = T.must(content[line]).gsub(tag_value, dependency_version)
            end
          end

          content
        end

        sig do
          params(
            value_node: Psych::Nodes::Scalar,
            content: T::Array[String],
            dependency_version: String
          ).returns(T::Array[String])
        end
        def update_scalar_image_tag(value_node, content, dependency_version)
          dependency_name = dependency.name

          dependency.requirements.each do |req|
            next unless req.metadata_symbol("type") == :docker_image

            old_tag = req.source_string("tag")
            next unless old_tag
            # digest-pinned images resolve by digest, so a tag-only bump would silently keep the old image
            next if req.source_string("digest")

            old_declaration = scalar_image_declaration(dependency_name, req, old_tag)
            # clip/keep chomping (plain > or |) leaves 1+ trailing newlines in the parsed value
            next unless value_node.value.sub(/\n+\z/, "") == old_declaration

            new_declaration = scalar_image_declaration(dependency_name, req, dependency_version)
            replace_within_node_span(value_node, content, old_declaration, new_declaration)
          end

          content
        end

        sig do
          params(
            value_node: Psych::Nodes::Scalar,
            content: T::Array[String],
            old_declaration: String,
            new_declaration: String
          ).void
        end
        def replace_within_node_span(value_node, content, old_declaration, new_declaration)
          if value_node.start_line == value_node.end_line
            replace_within_single_line(value_node, content, old_declaration, new_declaration)
          else
            replace_within_multi_line(value_node, content, old_declaration, new_declaration)
          end
        end

        sig do
          params(
            value_node: Psych::Nodes::Scalar,
            content: T::Array[String],
            old_declaration: String,
            new_declaration: String
          ).void
        end
        def replace_within_single_line(value_node, content, old_declaration, new_declaration)
          line = T.must(content[value_node.start_line])
          prefix = line[0...value_node.start_column]
          # bounding at end_column too keeps the search from bleeding into whatever
          # follows the node (e.g. a sibling key sharing the line)
          node_text = T.must(line[value_node.start_column...value_node.end_column])
          suffix = T.must(line[value_node.end_column..])
          return unless node_text.include?(old_declaration)

          content[value_node.start_line] = "#{prefix}#{node_text.sub(old_declaration, new_declaration)}#{suffix}"
        end

        sig do
          params(
            value_node: Psych::Nodes::Scalar,
            content: T::Array[String],
            old_declaration: String,
            new_declaration: String
          ).void
        end
        def replace_within_multi_line(value_node, content, old_declaration, new_declaration)
          lines = T.must(content[value_node.start_line..value_node.end_line])
          prefix = T.must(lines.first)[0...value_node.start_column]
          suffix = T.must(T.must(lines.last)[value_node.end_column..])
          node_text = node_span_text(lines, value_node.start_column, value_node.end_column)
          return unless node_text.include?(old_declaration)

          updated_lines = node_text.sub(old_declaration, new_declaration).split("\n", -1)
          updated_lines[0] = "#{prefix}#{updated_lines.first}"
          updated_lines[-1] = "#{updated_lines.last}#{suffix}"
          content[value_node.start_line..value_node.end_line] = updated_lines
        end

        sig do
          params(
            lines: T::Array[String],
            start_column: Integer,
            end_column: Integer
          ).returns(String)
        end
        def node_span_text(lines, start_column, end_column)
          middle_lines = T.must(lines[1..-2])
          first_segment = T.must(T.must(lines.first)[start_column..])
          last_segment = T.must(T.must(lines.last)[0...end_column])
          ([first_segment] + middle_lines + [last_segment]).join("\n")
        end

        sig do
          params(
            name: String,
            req: Dependabot::DependencyRequirement,
            tag: String
          ).returns(String)
        end
        def scalar_image_declaration(name, req, tag)
          registry = req.source_string("registry")
          # the parser already folds a detected registry into the name itself (e.g. "docker.io/nginx")
          declaration = registry && !name.start_with?("#{registry}/") ? "#{registry}/#{name}" : name
          "#{declaration}:#{tag}"
        end
      end
    end
  end
end
